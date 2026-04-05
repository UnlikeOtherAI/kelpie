package com.kelpie.browser.nativecore

class AiManager(modelsDir: String) {
    private val handle: Long = aiManagerCreateNative(modelsDir)

    fun destroy() = aiManagerDestroyNative(handle)

    var hfToken: String
        get() = aiGetHfToken(handle) ?: ""
        set(value) = aiSetHfToken(handle, value)

    fun listApprovedModels(): String = aiListApprovedModels(handle) ?: "[]"
    fun modelFitness(modelId: String, ramGB: Double, diskGB: Double): String =
        aiModelFitness(handle, modelId, ramGB, diskGB) ?: "{}"
    fun isModelDownloaded(modelId: String): Boolean = aiIsModelDownloaded(handle, modelId)
    fun modelPath(modelId: String): String = aiModelPath(handle, modelId) ?: ""
    fun removeModel(modelId: String): Boolean = aiRemoveModel(handle, modelId)
    fun setOllamaEndpoint(endpoint: String) = aiSetOllamaEndpoint(handle, endpoint)
    fun ollamaReachable(): Boolean = aiOllamaReachable(handle)
    fun ollamaListModels(): String = aiOllamaListModels(handle) ?: "[]"
    fun ollamaInfer(model: String, requestJson: String): String =
        aiOllamaInfer(handle, model, requestJson) ?: "{}"

    private external fun aiManagerCreateNative(modelsDir: String): Long
    private external fun aiManagerDestroyNative(handle: Long)
    private external fun aiSetHfToken(handle: Long, token: String)
    private external fun aiGetHfToken(handle: Long): String?
    private external fun aiListApprovedModels(handle: Long): String?
    private external fun aiModelFitness(handle: Long, modelId: String, ramGB: Double, diskGB: Double): String?
    private external fun aiIsModelDownloaded(handle: Long, modelId: String): Boolean
    private external fun aiModelPath(handle: Long, modelId: String): String?
    private external fun aiRemoveModel(handle: Long, modelId: String): Boolean
    private external fun aiSetOllamaEndpoint(handle: Long, endpoint: String)
    private external fun aiOllamaReachable(handle: Long): Boolean
    private external fun aiOllamaListModels(handle: Long): String?
    private external fun aiOllamaInfer(handle: Long, model: String, requestJson: String): String?

    companion object {
        init {
            System.loadLibrary("kelpie_jni")
        }
    }
}
