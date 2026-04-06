package com.airbridge.sms

import android.content.ContentResolver
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.ContactsContract
import android.provider.Telephony
import android.telephony.SmsManager
import android.util.Log
import com.airbridge.protocol.SmsConversation
import com.airbridge.protocol.SmsMessage

class SmsProvider(private val context: Context) {

    private val contentResolver: ContentResolver = context.contentResolver

    fun getConversations(page: Int, pageSize: Int): Pair<List<SmsConversation>, Int> {
        val conversations = mutableListOf<SmsConversation>()
        val seen = mutableSetOf<String>()

        val cursor = contentResolver.query(
            Telephony.Sms.CONTENT_URI,
            arrayOf(Telephony.Sms.THREAD_ID, Telephony.Sms.ADDRESS, Telephony.Sms.BODY, Telephony.Sms.DATE, Telephony.Sms.READ),
            null, null,
            "${Telephony.Sms.DATE} DESC"
        )

        var total = 0
        val offset = page * pageSize

        cursor?.use {
            while (it.moveToNext()) {
                val threadId = it.getString(0) ?: continue
                if (seen.contains(threadId)) continue
                seen.add(threadId)
                total++

                if (total <= offset) continue
                if (conversations.size >= pageSize) continue

                val address = it.getString(1) ?: ""
                val snippet = it.getString(2) ?: ""
                val date = it.getLong(3)

                conversations.add(SmsConversation(
                    threadId = threadId,
                    address = address,
                    displayName = getContactName(address) ?: address,
                    snippet = snippet,
                    date = date,
                    messageCount = getMessageCount(threadId),
                    unreadCount = getUnreadCount(threadId)
                ))
            }
        }

        return Pair(conversations, total)
    }

    fun getMessages(threadId: String, page: Int, pageSize: Int): Pair<List<SmsMessage>, Int> {
        val messages = mutableListOf<SmsMessage>()

        val countCursor = contentResolver.query(
            Telephony.Sms.CONTENT_URI,
            arrayOf(Telephony.Sms._ID),
            "${Telephony.Sms.THREAD_ID} = ?",
            arrayOf(threadId),
            null
        )
        val totalCount = countCursor?.count ?: 0
        countCursor?.close()

        val queryBundle = Bundle().apply {
            putStringArray(ContentResolver.QUERY_ARG_SORT_COLUMNS, arrayOf(Telephony.Sms.DATE))
            putInt(ContentResolver.QUERY_ARG_SORT_DIRECTION, ContentResolver.QUERY_SORT_DIRECTION_DESCENDING)
            putInt(ContentResolver.QUERY_ARG_LIMIT, pageSize)
            putInt(ContentResolver.QUERY_ARG_OFFSET, page * pageSize)
            putString(ContentResolver.QUERY_ARG_SQL_SELECTION, "${Telephony.Sms.THREAD_ID} = ?")
            putStringArray(ContentResolver.QUERY_ARG_SQL_SELECTION_ARGS, arrayOf(threadId))
        }

        val cursor = contentResolver.query(
            Telephony.Sms.CONTENT_URI,
            arrayOf(Telephony.Sms._ID, Telephony.Sms.ADDRESS, Telephony.Sms.BODY, Telephony.Sms.DATE, Telephony.Sms.TYPE, Telephony.Sms.READ),
            queryBundle,
            null
        )

        cursor?.use {
            while (it.moveToNext()) {
                messages.add(SmsMessage(
                    id = it.getString(0) ?: "",
                    address = it.getString(1) ?: "",
                    body = it.getString(2) ?: "",
                    date = it.getLong(3),
                    type = it.getInt(4),
                    read = it.getInt(5) == 1
                ))
            }
        }

        return Pair(messages, totalCount)
    }

    fun sendSms(address: String, body: String): Pair<Boolean, String?> {
        return try {
            @Suppress("DEPRECATION")
            val smsManager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                context.getSystemService(SmsManager::class.java)
            } else {
                SmsManager.getDefault()
            }
            val parts = smsManager.divideMessage(body)
            if (parts.size == 1) {
                smsManager.sendTextMessage(address, null, body, null, null)
            } else {
                smsManager.sendMultipartTextMessage(address, null, parts, null, null)
            }
            Pair(true, null)
        } catch (e: Exception) {
            Log.e("SmsProvider", "Send SMS failed", e)
            Pair(false, e.message)
        }
    }

    private fun getContactName(phoneNumber: String): String? {
        if (phoneNumber.isBlank()) return null
        val uri = Uri.withAppendedPath(
            ContactsContract.PhoneLookup.CONTENT_FILTER_URI,
            Uri.encode(phoneNumber)
        )
        val cursor = contentResolver.query(uri, arrayOf(ContactsContract.PhoneLookup.DISPLAY_NAME), null, null, null)
        return cursor?.use {
            if (it.moveToFirst()) it.getString(0) else null
        }
    }

    private fun getMessageCount(threadId: String): Int {
        val cursor = contentResolver.query(
            Telephony.Sms.CONTENT_URI,
            arrayOf(Telephony.Sms._ID),
            "${Telephony.Sms.THREAD_ID} = ?",
            arrayOf(threadId),
            null
        )
        val count = cursor?.count ?: 0
        cursor?.close()
        return count
    }

    private fun getUnreadCount(threadId: String): Int {
        val cursor = contentResolver.query(
            Telephony.Sms.CONTENT_URI,
            arrayOf(Telephony.Sms._ID),
            "${Telephony.Sms.THREAD_ID} = ? AND ${Telephony.Sms.READ} = 0",
            arrayOf(threadId),
            null
        )
        val count = cursor?.count ?: 0
        cursor?.close()
        return count
    }
}
