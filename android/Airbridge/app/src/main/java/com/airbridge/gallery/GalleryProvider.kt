package com.airbridge.gallery

import android.content.ContentResolver
import android.content.ContentUris
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore
import android.util.Base64
import android.util.Log
import com.airbridge.protocol.PhotoMeta
import java.io.ByteArrayOutputStream

class GalleryProvider(private val contentResolver: ContentResolver) {

    fun getPhotos(page: Int, pageSize: Int): Pair<List<PhotoMeta>, Int> {
        val photos = mutableListOf<PhotoMeta>()

        val projection = arrayOf(
            MediaStore.Images.Media._ID,
            MediaStore.Images.Media.DISPLAY_NAME,
            MediaStore.Images.Media.DATE_TAKEN,
            MediaStore.Images.Media.DATE_MODIFIED,
            MediaStore.Images.Media.WIDTH,
            MediaStore.Images.Media.HEIGHT,
            MediaStore.Images.Media.SIZE,
            MediaStore.Images.Media.MIME_TYPE
        )

        // Get total count first
        val countCursor = contentResolver.query(
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
            arrayOf(MediaStore.Images.Media._ID),
            null, null, null
        )
        val totalCount = countCursor?.count ?: 0
        countCursor?.close()

        // Get page using Bundle for API 30+ compatibility
        val offset = page * pageSize
        val queryBundle = Bundle().apply {
            putStringArray(ContentResolver.QUERY_ARG_SORT_COLUMNS, arrayOf(MediaStore.Images.Media.DATE_TAKEN))
            putInt(ContentResolver.QUERY_ARG_SORT_DIRECTION, ContentResolver.QUERY_SORT_DIRECTION_DESCENDING)
            putInt(ContentResolver.QUERY_ARG_LIMIT, pageSize)
            putInt(ContentResolver.QUERY_ARG_OFFSET, offset)
        }
        val cursor = contentResolver.query(
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
            projection,
            queryBundle,
            null
        )

        cursor?.use {
            val idCol = it.getColumnIndexOrThrow(MediaStore.Images.Media._ID)
            val nameCol = it.getColumnIndexOrThrow(MediaStore.Images.Media.DISPLAY_NAME)
            val dateTakenCol = it.getColumnIndexOrThrow(MediaStore.Images.Media.DATE_TAKEN)
            val dateModCol = it.getColumnIndexOrThrow(MediaStore.Images.Media.DATE_MODIFIED)
            val widthCol = it.getColumnIndexOrThrow(MediaStore.Images.Media.WIDTH)
            val heightCol = it.getColumnIndexOrThrow(MediaStore.Images.Media.HEIGHT)
            val sizeCol = it.getColumnIndexOrThrow(MediaStore.Images.Media.SIZE)
            val mimeCol = it.getColumnIndexOrThrow(MediaStore.Images.Media.MIME_TYPE)

            while (it.moveToNext()) {
                // DATE_TAKEN is millis, DATE_MODIFIED is seconds — normalize to millis
                val dateTaken = it.getLong(dateTakenCol)
                val dateMod = it.getLong(dateModCol) * 1000
                val date = if (dateTaken > 0) dateTaken else dateMod

                photos.add(
                    PhotoMeta(
                        id = it.getLong(idCol).toString(),
                        filename = it.getString(nameCol) ?: "unknown",
                        dateTaken = date,
                        width = it.getInt(widthCol),
                        height = it.getInt(heightCol),
                        size = it.getLong(sizeCol),
                        mimeType = it.getString(mimeCol) ?: "image/jpeg"
                    )
                )
            }
        }

        return Pair(photos, totalCount)
    }

    fun getThumbnail(photoId: String): String? {
        val id = photoId.toLongOrNull() ?: return null
        val uri = ContentUris.withAppendedId(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, id)

        return try {
            // First pass: get dimensions only
            val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            val tempStream = contentResolver.openInputStream(uri) ?: return null
            BitmapFactory.decodeStream(tempStream, null, options)
            tempStream.close()

            // Calculate sample size for ~400px target (good enough for grid thumbnails)
            val targetSize = 400
            val width = options.outWidth
            val height = options.outHeight
            var sampleSize = 1
            while (width / sampleSize > targetSize * 2 || height / sampleSize > targetSize * 2) {
                sampleSize *= 2
            }

            // Second pass: decode with sample size
            val decodeOptions = BitmapFactory.Options().apply { inSampleSize = sampleSize }
            val stream2 = contentResolver.openInputStream(uri) ?: return null
            val bitmap = BitmapFactory.decodeStream(stream2, null, decodeOptions)
            stream2.close()

            if (bitmap == null) return null

            // Scale to exact target if still too large
            val scaledBitmap = if (bitmap.width > targetSize || bitmap.height > targetSize) {
                val scale = targetSize.toFloat() / maxOf(bitmap.width, bitmap.height)
                val newW = (bitmap.width * scale).toInt()
                val newH = (bitmap.height * scale).toInt()
                val scaled = Bitmap.createScaledBitmap(bitmap, newW, newH, true)
                if (scaled !== bitmap) bitmap.recycle()
                scaled
            } else {
                bitmap
            }

            val out = ByteArrayOutputStream()
            scaledBitmap.compress(Bitmap.CompressFormat.JPEG, 75, out)
            scaledBitmap.recycle()

            Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP)
        } catch (e: Exception) {
            Log.e("GalleryProvider", "Thumbnail failed for $photoId", e)
            null
        }
    }

    fun getPhotoUri(photoId: String): android.net.Uri? {
        val id = photoId.toLongOrNull() ?: return null
        return ContentUris.withAppendedId(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, id)
    }
}
