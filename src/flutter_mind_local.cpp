/**
 * @file flutter_mind_local.cpp
 * @brief On-device LLM inference via llama.cpp.
 *
 * Design notes:
 *
 * GLOBALS — llama.cpp is not designed to be instantiated multiple times in the
 * same process. One model + one context is the standard usage pattern. All state
 * lives in module-level statics so the C API stays simple (no handle to pass around).
 *
 * CHAT TEMPLATES — each model family uses a different prompt format. We apply
 * the correct template in format_prompt() before tokenising. Wrong template =
 * the model ignores the system prompt or repeats the conversation back.
 *
 * STOP SEQUENCES — llama_vocab_is_eog() catches the model's built-in EOS token,
 * but chat models also emit format-specific stop strings (e.g. <|im_end|> for Qwen).
 * We check ends_with_stop() after every token so generation stops immediately,
 * not after 512 garbage tokens.
 *
 * SYSTEM PROMPT OWNERSHIP — Dart allocates native strings, passes them to C++,
 * then frees them after the call returns. Any pointer we store past that point
 * is a dangling pointer. We copy system_prompt into g_system_prompt_buf so C++
 * owns the memory. stop_sequences is safe because parse_stop_sequences() copies
 * into std::string before the caller frees the buffer.
 */

#include "flutter_mind_local.h"
#include <llama.h>
#include <string>
#include <vector>
#include <cstring>
#include <thread>

// ─── Globals ─────────────────────────────────────────────────────────────────

static llama_model *g_model = nullptr;
static llama_context *g_context = nullptr;
static std::string g_response;
static FlutterMindLocalConfig g_config;
static std::vector<std::string> g_stop_sequences;

// Streaming generation state — lives across flutter_mind_local_prompt_start()
// and repeated flutter_mind_local_prompt_next() calls. Owned by whichever of
// the two ever ran most recently; flutter_mind_local_prompt() also goes
// through these same globals via the two functions internally.
static llama_sampler *g_sampler = nullptr;
static int g_tokens_generated = 0;
static std::string g_token_buf; // text of the single token returned by the most recent prompt_next() call

// Owns the system prompt string. Dart frees its native buffer after init
// returns, so we copy here to avoid a dangling pointer in format_prompt().
static char g_system_prompt_buf[4096] = {};

// ─── Model type detection ─────────────────────────────────────────────────────

// Reads the "general.architecture" key from the .gguf metadata and maps it
// to a model type index. Returns 0 (unknown/fallback) if the key is missing.
static int detect_model_type()
{
    char arch_buf[64] = {};
    int len = llama_model_meta_val_str(g_model, "general.architecture", arch_buf, sizeof(arch_buf));
    if (len <= 0)
        return 0;
    std::string a(arch_buf);
    if (a == "qwen2")
        return 1;
    if (a == "llama")
        return 2;
    if (a == "gemma")
        return 3;
    if (a == "gemma2")
        return 3; // same template as gemma
    if (a == "gemma3")
        return 3;
    if (a == "phi2")
        return 4;
    if (a == "phi3")
        return 4; // same template as phi
    if (a == "mistral")
        return 5;
    if (a == "deepseek2")
        return 6;
    return 0;
}

// ─── Chat template formatting ─────────────────────────────────────────────────

// Wraps the user prompt in the correct chat template for the loaded model.
// Each model family was trained on a specific format — using the wrong one
// causes the model to echo the prompt, ignore the system message, or produce
// incoherent output.
static std::string format_prompt(const char *prompt)
{
    int type = g_config.model_type;
    if (type == 0)
        type = detect_model_type(); // auto-detect from .gguf metadata

    std::string sys = g_config.system_prompt
                          ? g_config.system_prompt
                          : "You are a helpful assistant.";

    if (type == 1) // Qwen 2 / 2.5 — ChatML format
        return "<|im_start|>system\n" + sys + "<|im_end|>\n" + "<|im_start|>user\n" + prompt + "<|im_end|>\n" + "<|im_start|>assistant\n";

    if (type == 2) // Llama 3 / 3.2 — header-based format
        return "<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n" + sys + "\n<|start_header_id|>user<|end_header_id|>\n" + prompt + "\n<|start_header_id|>assistant<|end_header_id|>\n";

    if (type == 3) // Gemma 1 / 2 / 3 — turn-based format
        return "<start_of_turn>user\n" + sys + "\n" + prompt + "<end_of_turn>\n<start_of_turn>model\n";

    if (type == 4) // Phi 2 / 3 / 4 — pipe-delimited format
        return "<|system|>\n" + sys + "<|end|>\n" + "<|user|>\n" + prompt + "<|end|>\n" + "<|assistant|>\n";

    if (type == 5) // Mistral — INST-based format
        return "[INST] " + sys + "\n" + prompt + " [/INST]";

    if (type == 6) // DeepSeek — sentence-boundary format
        return "<|begin▁of▁sentence|>" + sys + "\n\nUser: " + prompt + "\n\nAssistant:";

    // Unknown model — plain system + prompt, no special tokens
    return sys + "\n" + prompt;
}

// ─── Stop sequence helpers ────────────────────────────────────────────────────

// Splits a \x1F-delimited string into a vector of stop sequences.
// \x1F (ASCII unit separator) is used because it never appears in chat tokens.
static std::vector<std::string> parse_stop_sequences(const char *raw)
{
    std::vector<std::string> result;
    if (!raw || raw[0] == '\0')
        return result;
    std::string s(raw);
    size_t start = 0, pos;
    while ((pos = s.find('\x1F', start)) != std::string::npos)
    {
        if (pos > start)
            result.push_back(s.substr(start, pos - start));
        start = pos + 1;
    }
    if (start < s.size())
        result.push_back(s.substr(start));
    return result;
}

// Returns true if the accumulated response ends with any registered stop sequence.
// Called after every token so we break immediately — not after 512 garbage tokens.
static bool ends_with_stop(const std::string &response)
{
    for (const auto &stop : g_stop_sequences)
    {
        if (response.size() >= stop.size() &&
            response.compare(response.size() - stop.size(), stop.size(), stop) == 0)
            return true;
    }
    return false;
}

// Removes the matching stop sequence from the end of the response string.
static void trim_stop(std::string &response)
{
    for (const auto &stop : g_stop_sequences)
    {
        if (response.size() >= stop.size() &&
            response.compare(response.size() - stop.size(), stop.size(), stop) == 0)
        {
            response.erase(response.size() - stop.size());
            return;
        }
    }
}

// ─── Init ─────────────────────────────────────────────────────────────────────

int flutter_mind_local_init(FlutterMindLocalConfig config)
{
    g_config = config;
    g_stop_sequences = parse_stop_sequences(config.stop_sequences);

    llama_backend_init();

    llama_model_params model_params = llama_model_default_params();
    g_model = llama_model_load_from_file(config.model_path, model_params);
    if (!g_model)
        return 1;

    llama_context_params context_params = llama_context_default_params();
    context_params.n_ctx = config.context_size > 0 ? config.context_size : 2048;
    context_params.n_threads = config.thread_count > 0 ? config.thread_count : std::thread::hardware_concurrency();

    g_context = llama_init_from_model(g_model, context_params);
    if (!g_context)
        return 1;

    return 0;
}

// Inference

// Tokenises the prompt and primes the KV cache + sampler chain for a fresh
// generation. Must be called once before any flutter_mind_local_prompt_next()
// calls. Generation state (g_sampler, g_tokens_generated, g_response) is
// reset here, not in prompt_next, so prompt_next can be called repeatedly
// without re-running setup.
//
// @return 0 on success, non-zero on failure (tokenisation error).
int flutter_mind_local_prompt_start(const char *prompt)
{
    // clear KV cache if context is almost full — prevents garbage output
    int n_used = llama_get_kv_cache_used_cells(g_context);
    int n_max = g_config.context_size > 0 ? g_config.context_size : 2048;
    if (n_used >= n_max - 100)
        llama_kv_cache_clear(g_context);

    // apply the correct chat template before tokenising
    std::string formatted = format_prompt(prompt);

    int max_ctx = g_config.context_size > 0 ? g_config.context_size : 2048;
    std::vector<llama_token> tokens(max_ctx);

    int n_tokens = llama_tokenize(
        llama_model_get_vocab(g_model),
        formatted.c_str(),
        (int32_t)formatted.size(),
        tokens.data(),
        (int32_t)tokens.size(),
        true,   // add BOS token
        false); // do not add EOS token
    if (n_tokens < 0)
        return -1;
    tokens.resize(n_tokens);

    // feed the prompt tokens into the KV cache
    llama_batch batch = llama_batch_get_one(tokens.data(), n_tokens);
    llama_decode(g_context, batch);

    // build sampler chain — order matters: top_k → top_p → temperature → penalty → dist
    // stored in g_sampler (not a local), so prompt_next can keep sampling
    // from the same chain across repeated calls.
    if (g_sampler)
    {
        llama_sampler_free(g_sampler);
        g_sampler = nullptr;
    }
    auto sparams = llama_sampler_chain_default_params();
    g_sampler = llama_sampler_chain_init(sparams);

    if (g_config.top_k > 0)
        llama_sampler_chain_add(g_sampler, llama_sampler_init_top_k(g_config.top_k));

    if (g_config.top_p > 0)
        llama_sampler_chain_add(g_sampler, llama_sampler_init_top_p(g_config.top_p, 1));

    float temp = g_config.temperature > 0 ? g_config.temperature : 0.7f;
    llama_sampler_chain_add(g_sampler, llama_sampler_init_temp(temp));

    // penalty_last_n=64: look back 64 tokens for repeats
    float penalty = g_config.repeat_penalty > 0 ? g_config.repeat_penalty : 1.1f;
    llama_sampler_chain_add(g_sampler, llama_sampler_init_penalties(64, penalty, 0.0f, 0.0f));

    uint32_t seed = g_config.seed > 0 ? (uint32_t)g_config.seed : LLAMA_DEFAULT_SEED;
    llama_sampler_chain_add(g_sampler, llama_sampler_init_dist(seed));

    g_tokens_generated = 0;
    g_response = "";

    return 0;
}

// Generates exactly one token and returns its text.
//
// KNOWN LIMITATION: stop sequences that span more than one token (e.g. a
// multi-token "<|im_end|>") can leak a partial fragment to the caller before
// the match completes, because each token is returned as soon as it's
// generated — unlike flutter_mind_local_prompt(), which only ever returns
// the fully-trimmed string. Most chat templates tokenise their stop strings
// as a single token in practice, so this is rarely hit, but it is a real gap.
//
// @return Null-terminated text for one token, or NULL when generation is
//         done (EOG token, stop sequence matched, or max_tokens reached).
//         The returned pointer is valid until the next prompt_next()/prompt()
//         call or flutter_mind_local_cleanup(). Do NOT free it from Dart.
const char *flutter_mind_local_prompt_next()
{
    int max = g_config.max_tokens > 0 ? g_config.max_tokens : 512;

    if (g_sampler == nullptr || g_tokens_generated >= max)
    {
        if (g_sampler)
        {
            llama_sampler_free(g_sampler);
            g_sampler = nullptr;
        }
        return nullptr;
    }

    llama_token token = llama_sampler_sample(g_sampler, g_context, -1);

    // model's built-in end-of-generation token (EOS/EOT)
    if (llama_vocab_is_eog(llama_model_get_vocab(g_model), token))
    {
        llama_sampler_free(g_sampler);
        g_sampler = nullptr;
        return nullptr;
    }

    // convert token id to text
    char buf[128];
    int n = llama_token_to_piece(
        llama_model_get_vocab(g_model),
        token, buf, sizeof(buf), 0, false);
    g_token_buf = n > 0 ? std::string(buf, n) : std::string();

    // user-defined stop sequences — stop immediately, don't generate further
    g_response += g_token_buf;
    if (ends_with_stop(g_response))
    {
        trim_stop(g_response);
        llama_sampler_free(g_sampler);
        g_sampler = nullptr;
        return nullptr;
    }

    // feed the generated token back as input for the next call
    llama_batch batch = llama_batch_get_one(&token, 1);
    llama_decode(g_context, batch);

    g_tokens_generated++;

    return g_token_buf.c_str();
}

// Runs a full prompt → response cycle in one call, returning the complete,
// stop-sequence-trimmed response. Built on top of prompt_start()/prompt_next()
// so there's a single implementation of the generation logic — this is the
// non-streaming counterpart used by Dart's send(), prompt_next() drives stream().
const char *flutter_mind_local_prompt(const char *prompt)
{
    if (flutter_mind_local_prompt_start(prompt) != 0)
        return nullptr;

    // prompt_next() already accumulates each token into the global
    // g_response itself (it needs the running string for stop-sequence
    // detection) — just drive it to completion, don't re-accumulate here.
    while (flutter_mind_local_prompt_next() != nullptr)
        ;

    // prompt_next already trims on a stop-sequence match, but max_tokens /
    // EOG exits don't — this is the same safety net the original
    // implementation had for stop sequences spanning a token boundary.
    trim_stop(g_response);

    return g_response.c_str();
}

// FFI entry point

// Flat-parameter wrapper called from Dart FFI.
// Avoids struct layout alignment issues between Dart and C++ by taking
// individual scalars instead of a struct. Maps 1-to-1 to FlutterMindLocalConfig.
extern "C" int flutter_mind_local_init_params(
    const char *model_path,
    const char *system_prompt,
    const char *stop_sequences,
    float temperature,
    int max_tokens,
    int context_size,
    float repeat_penalty,
    float top_p,
    int top_k,
    int seed,
    int thread_count,
    int model_type)
{
    FlutterMindLocalConfig config = {};

    config.model_path = model_path; // llama.cpp copies this internally — no ownership issue

    // Copy into stable storage. Dart frees its native buffer after this call
    // returns, so storing the raw pointer would be a dangling pointer.
    if (system_prompt && system_prompt[0])
    {
        strncpy(g_system_prompt_buf, system_prompt, sizeof(g_system_prompt_buf) - 1);
        g_system_prompt_buf[sizeof(g_system_prompt_buf) - 1] = '\0';
        config.system_prompt = g_system_prompt_buf;
    }
    else
    {
        config.system_prompt = nullptr;
    }

    // stop_sequences is safe to pass as-is — parse_stop_sequences() copies into
    // std::string before this function returns and the Dart buffer is freed.
    config.stop_sequences = (stop_sequences && stop_sequences[0]) ? stop_sequences : nullptr;

    config.temperature = temperature;
    config.max_tokens = max_tokens;
    config.context_size = context_size;
    config.repeat_penalty = repeat_penalty;
    config.top_p = top_p;
    config.top_k = top_k;
    config.seed = seed;
    config.thread_count = thread_count;
    config.model_type = model_type;

    return flutter_mind_local_init(config);
}

// Cleanup

void flutter_mind_local_cleanup()
{
    if (g_context)
    {
        llama_free(g_context);
        g_context = nullptr;
    }
    if (g_model)
    {
        llama_model_free(g_model);
        g_model = nullptr;
    }
    llama_backend_free();
}
