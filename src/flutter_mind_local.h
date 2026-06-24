/**
 * @file flutter_mind_local.h
 * @brief C API for on-device LLM inference via llama.cpp.
 *
 * Lifecycle:
 *   1. Call flutter_mind_local_init_params() once to load the model into memory.
 *   2. Call flutter_mind_local_prompt() for each user message — returns the response.
 *   3. Call flutter_mind_local_cleanup() when done to free model memory.
 *
 * All functions use C linkage so they can be called from Dart FFI without
 * name mangling. The implementation lives in flutter_mind_local.cpp.
 *
 * Thread safety: NOT thread-safe. Call from one thread (or one isolate) at
 * a time. Use Dart's Completer pattern to queue concurrent calls.
 */

#ifndef FLUTTER_MIND_LOCAL_H
#define FLUTTER_MIND_LOCAL_H

#ifdef __cplusplus
extern "C"
{
#endif

    /**
     * Configuration passed to flutter_mind_local_init().
     *
     * All pointer fields must remain valid for the duration of the init call.
     * The implementation copies strings it needs to retain (e.g. system_prompt)
     * into its own storage — callers may free their buffers after init returns.
     */
    typedef struct FlutterMindLocalConfig
    {
        const char *model_path;     // absolute path to the .gguf model file
        const char *system_prompt;  // persona/instructions — copied into static buffer on init
        const char *stop_sequences; // \x1F-delimited list e.g. "<|im_end|>\x1F<|im_start|>", or NULL
        float temperature;          // output randomness — 0.0 (deterministic) to 2.0 (creative)
        int max_tokens;             // max tokens to generate per response
        int context_size;           // KV-cache size in tokens — limits conversation memory
        float repeat_penalty;       // penalise repeated tokens — 1.0 = off, 1.1+ = reduce loops
        float top_p;                // nucleus sampling threshold — 0.0–1.0
        int top_k;                  // top-K sampling pool size — 0 = disabled
        int seed;                   // RNG seed for reproducible output — -1 = random
        int thread_count;           // CPU threads for inference — 4 recommended on mobile
        int model_type;             // chat template index — see FlutterMindLocalType in local_config.dart
    } FlutterMindLocalConfig;

    /**
     * Initialises the model from a FlutterMindLocalConfig struct.
     *
     * Loads the .gguf file, allocates KV cache, and sets up the sampler chain.
     * Blocks until the model is fully loaded — call from a background isolate.
     *
     * @return 0 on success, non-zero on failure (file not found, OOM, etc.)
     */
    int flutter_mind_local_init(FlutterMindLocalConfig config);

    /**
     * Flat-parameter wrapper around flutter_mind_local_init — easier to call from Dart FFI.
     *
     * Avoids struct layout alignment issues between Dart and C++.
     * Parameters map 1-to-1 to FlutterMindLocalConfig fields.
     *
     * @param stop_sequences  \x1F-delimited stop strings, or "" for none.
     * @return 0 on success, non-zero on failure.
     */
    int flutter_mind_local_init_params(
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
        int model_type);

    /**
     * Runs inference for a single user prompt and returns the response.
     *
     * Applies the correct chat template for the loaded model type, tokenises
     * the prompt, runs the generation loop, and stops when a stop sequence
     * is hit or max_tokens is reached.
     *
     * The returned pointer is valid until the next call to flutter_mind_local_prompt()
     * or flutter_mind_local_cleanup(). Do NOT free it from Dart.
     *
     * @param prompt  The full conversation string (history + user message).
     * @return        Null-terminated response string, or NULL on error.
     */
    const char *flutter_mind_local_prompt(const char *prompt);

    /**
     * Tokenises the prompt and primes generation state for streaming.
     * Call once, then call flutter_mind_local_prompt_next() in a loop until
     * it returns NULL.
     *
     * Do NOT call flutter_mind_local_prompt() while a prompt_next() loop is
     * in progress — both share the same generation state (g_sampler,
     * g_response) and will corrupt each other's output.
     *
     * @param prompt  The full conversation string (history + user message).
     * @return        0 on success, non-zero on failure (tokenisation error).
     */
    int flutter_mind_local_prompt_start(const char *prompt);

    /**
     * Generates and returns exactly one token's text. Call repeatedly after
     * flutter_mind_local_prompt_start() until it returns NULL.
     *
     * KNOWN LIMITATION: a stop sequence spanning more than one token can leak
     * a partial fragment before the match completes, since each token is
     * returned as soon as it's generated. flutter_mind_local_prompt() doesn't
     * have this issue because it only ever returns the fully-trimmed string.
     *
     * The returned pointer is valid until the next prompt_next()/prompt()
     * call or flutter_mind_local_cleanup(). Do NOT free it from Dart.
     *
     * @return  Text for one token, or NULL when generation is done (EOG
     *          token, stop sequence matched, or max_tokens reached).
     */
    const char *flutter_mind_local_prompt_next();

    /**
     * Frees the model, context, and sampler from memory.
     *
     * Call once when the engine is disposed. After this, flutter_mind_local_init_params()
     * must be called again before using flutter_mind_local_prompt().
     */
    void flutter_mind_local_cleanup();
#ifdef __cplusplus
}
#endif

#endif // FLUTTER_MIND_LOCAL_H