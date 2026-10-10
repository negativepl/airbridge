import XCTest
@testable import AirbridgeApp

final class OneTimeCodeTests: XCTestCase {
    func testFindsCodesInRealMessages() {
        XCTAssertEqual(OneTimeCode.find(in: "Jednorazowy kod konta Microsoft: 140125"), "140125")
        XCTAssertEqual(OneTimeCode.find(in: "Kod resetowania hasła do konta Microsoft: 451954"), "451954")
        XCTAssertEqual(OneTimeCode.find(in: "Inpost: Twoj kod weryfikacyjny to 788210 Pozdrawiamy, Zespol InPost"), "788210")
        XCTAssertEqual(OneTimeCode.find(in: "Twoj kod sms: 005466\n\nWyU7UcJNnRw"), "005466")
        XCTAssertEqual(OneTimeCode.find(in: "Wpisz kod aktywacyjny: 5655"), "5655")
        XCTAssertEqual(OneTimeCode.find(in: "778548 is your Link verification code"), "778548")
        XCTAssertEqual(OneTimeCode.find(in: "Klarna: 589972 to Twój kod. Nie udostępniaj go nikomu."), "589972")
        XCTAssertEqual(OneTimeCode.find(in: "Halo odbior! Old Spice zel pod... jest w Zabka, Szeroka 20, Koszalin. Przesylka AD0FRQK1Z9K8Z49QJ. Kod odbioru 678 438"), "678438")
    }

    func testIgnoresMessagesWithoutACode() {
        XCTAssertNil(OneTimeCode.find(in: "Jasne, potwierdzam, że będę."))
        XCTAssertNil(OneTimeCode.find(in: "Jesienne plany? Do 54400 zl na dowod. Zadzwon pod 717732844 (koszt wg op.)."))
        XCTAssertNil(OneTimeCode.find(in: "Microsoft: Zmieniono haslo do konta ba**n@ou**.com. To nie Ty? aka.ms/alcr"))
        XCTAssertNil(OneTimeCode.find(in: "Pogoda: dzis i jutro (20/21.09) prognozowany silny wiatr."))
        XCTAssertNil(OneTimeCode.find(in: "Twoja wizyta z 02.09.2026 o 18:00 zostala odwolana."))
    }
}
