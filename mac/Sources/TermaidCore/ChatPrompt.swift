/// The LFM3 chat format from training/Modelfile-lfm3, with thinking disabled as in training.
/// Split at the user text so the part before it, shared by every call, can be cached.
enum ChatPrompt {
    static func lfm3Head(system: String) -> String {
        "<|im_start|>system\n\(system)<|im_end|>\n<|im_start|>user\n"
    }

    static func lfm3Tail(user: String) -> String {
        "\(user)<|im_end|>\n<|im_start|>assistant\n<think></think>"
    }
}
