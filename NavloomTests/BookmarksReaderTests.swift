import Testing
import Foundation
@testable import Navloom

struct BookmarksReaderTests {

    @Test func aplatitLesDossiersImbriques() throws {
        let json = """
        {"roots":{
          "bookmark_bar":{"name":"Barre","type":"folder","children":[
            {"name":"Apple","type":"url","url":"https://apple.com/"},
            {"name":"Dossier","type":"folder","children":[
              {"name":"Swift","type":"url","url":"https://swift.org/"}
            ]}
          ]},
          "other":{"name":"Autres","type":"folder","children":[]}
        }}
        """
        let bookmarks = try BookmarksReader.parse(Data(json.utf8))
        #expect(bookmarks.map(\.url) == ["https://apple.com/", "https://swift.org/"])
    }
}
