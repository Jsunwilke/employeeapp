package com.my.focalpoint.utils

import com.google.gson.*
import com.my.focalpoint.data.remote.ClaudeContent
import java.lang.reflect.Type

class ClaudeContentTypeAdapter : JsonSerializer<ClaudeContent>, JsonDeserializer<ClaudeContent> {

    override fun serialize(
        src: ClaudeContent,
        typeOfSrc: Type,
        context: JsonSerializationContext
    ): JsonElement {
        return when (src) {
            is ClaudeContent.Text -> context.serialize(src)
            is ClaudeContent.Image -> context.serialize(src)
        }
    }

    override fun deserialize(
        json: JsonElement,
        typeOfT: Type,
        context: JsonDeserializationContext
    ): ClaudeContent {
        val jsonObject = json.asJsonObject
        val type = jsonObject.get("type").asString

        return when (type) {
            "text" -> context.deserialize(json, ClaudeContent.Text::class.java)
            "image" -> context.deserialize(json, ClaudeContent.Image::class.java)
            else -> throw JsonParseException("Unknown type: $type")
        }
    }
}
