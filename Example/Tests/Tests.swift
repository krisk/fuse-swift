import UIKit
import XCTest
import Fuse

class Tests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testBasic() {
        let fuse = Fuse()
        
        var pattern = fuse.createPattern(from: "od mn war")
        var result = fuse.search(pattern, in: "Old Man's War")
        
        XCTAssert(result?.score == 0.44444444444444442, "Score is good")
        XCTAssert(result?.ranges.count == 3, "Found the correct number of ranges")
        
        pattern = fuse.createPattern(from: "uni manheim")
        result = fuse.search(pattern, in: "university manheim")
        XCTAssert(result?.ranges.count == 4, "Found the correct number of ranges")
        
        pattern = fuse.createPattern(from: "unimanheim")
        result = fuse.search(pattern, in: "university manheim")
        XCTAssert(result?.ranges.count == 4, "Found the correct number of ranges")
        
        pattern = fuse.createPattern(from: "xyz")
        result = fuse.search(pattern, in: "abc")
        XCTAssert(result == nil, "No result")
        
        pattern = fuse.createPattern(from: "")
        result = fuse.search(pattern, in: "abc")
        XCTAssert(result == nil, "No result")
        
        pattern = fuse.createPattern(from: "")
        result = fuse.search(pattern, in: "abc")
        XCTAssert(result == nil, "No result")
    }
    
    func testSequence() {
        let books = ["The Lock Artist", "The Lost Symbol", "The Silmarillion", "xyz", "fga"]
        
        let fuse = Fuse()
        let results = fuse.search("Te silm", in: books)
        
        XCTAssert(results.count > 0, "There are results")
        XCTAssert(results[0].index == 2, "The first result is the third book")
        XCTAssert(results[1].index == 1, "The second result is the second book")
    }

    func testRange() {
        let books = ["The Lock Artist", "The Lost Symbol", "The Silmarillion", "xyz", "fga"]

        let fuse = Fuse()
        let results = fuse.search("silm", in: books)

        XCTAssert(results[0].ranges.count == 1, "There is a matching range in the first result")
        XCTAssert(results[0].ranges[0] == CountableClosedRange(4...7), "The range goes over the matched substring")
    }
    
    func testProtocolWeightedSearch1() {
        class Book: Fuseable {
            dynamic let author: String
            dynamic let title: String
            
            public init (author: String, title: String) {
                self.author = author
                self.title = title
            }
            
            var properties: [FuseProperty] {
                return [
                    FuseProperty(name: "title", weight: 0.7),
                    FuseProperty(name: "author", weight: 0.3),
                ]
            }
        }
        
        let books: [Book] = [
            Book(author: "John X", title: "Old Man's War fiction"),
            Book(author: "P.D. Mans", title: "Right Ho Jeeves")
        ]
        
        let fuse = Fuse()
        let results = fuse.search("man", in: books)
        
        XCTAssert(results.count > 0, "There are results")
        XCTAssert(results[0].index == 0, "The first result is the first book")
        XCTAssert(results[1].index == 1, "The second result is the second book")
    }
    
    func testProtocolWeightedSearch2() {
        class Book: Fuseable {
            dynamic let author: String
            dynamic let title: String
            
            public init (author: String, title: String) {
                self.author = author
                self.title = title
            }
            
            var properties: [FuseProperty] {
                return [
                    FuseProperty(name: "title", weight: 0.3),
                    FuseProperty(name: "author", weight: 0.7),
                ]
            }
        }
        
        let books: [Book] = [
            Book(author: "John X", title: "Old Man's War fiction"),
            Book(author: "P.D. Mans", title: "Right Ho Jeeves")
        ]
        
        let fuse = Fuse()
        let results = fuse.search("man", in: books)
        
        XCTAssert(results.count > 0, "There are results")
        XCTAssert(results[0].index == 1, "The first result is the second book")
        XCTAssert(results[1].index == 0, "The second result is the first book")
    }
    
    func testPerformanceSync() {
        if let path = Bundle(for: type(of: self)).path(forResource: "books", ofType: "txt") {
            do {
                let data = try String(contentsOfFile: path, encoding: .utf8)
                let books = data.components(separatedBy: .newlines)
                let fuse = Fuse()
                
                self.measure {
                    _ = fuse.search("Th tinsg", in: books)
                }
            } catch {
                print(error)
            }
        }
    }
    
    func testPerformanceAsync() {
        if let path = Bundle(for: type(of: self)).path(forResource: "books", ofType: "txt") {
            do {
                let data = try String(contentsOfFile: path, encoding: .utf8)
                let books = data.components(separatedBy: .newlines)
                let fuse = Fuse()
                
                self.measure {
                    let expect = self.expectation(description: "searching")
                    fuse.search("Th tinsg", in: books, completion: { results in
                        expect.fulfill()
                    })
                    self.wait(for: [expect], timeout: 20000000)
                }
            } catch {
                print(error)
            }
        }
    }
}
