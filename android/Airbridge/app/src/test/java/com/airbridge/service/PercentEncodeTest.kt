package com.airbridge.service

import org.junit.Assert.assertEquals
import org.junit.Test

class PercentEncodeTest {
    @Test fun spaceIsPercent20() = assertEquals("Skan%202026-11-08%2018.50.18.pdf", percentEncode("Skan 2026-11-08 18.50.18.pdf"))
    @Test fun plusStaysAPlus() = assertEquals("C%2B%2B%20notes.txt", percentEncode("C++ notes.txt"))
    @Test fun polishLetters() = assertEquals("Zdj%C4%99cie.jpg", percentEncode("Zdjęcie.jpg"))
    @Test fun folderPath() = assertEquals("Documents%2FNowy%20folder", percentEncode("Documents/Nowy folder"))
}
