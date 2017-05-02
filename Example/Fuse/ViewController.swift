//
//  ViewController.swift
//  Fuse
//
//  Created by Kirollos Risk on 05/02/2017.
//  Copyright (c) 2017 Kirollos Risk. All rights reserved.
//

import UIKit
import Fuse

struct Item {
    let name : String
}

class ViewController: UITableViewController {
    
    // MARK: - Properties
    var books = [String]()
    var filteredBooks = [NSMutableAttributedString]()
    let fuse = Fuse()
    
    let searchController = UISearchController(searchResultsController: nil)
    
    // MARK: - View Setup
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Setup the Search Controller
        searchController.searchResultsUpdater = self
        searchController.searchBar.delegate = self
        definesPresentationContext = true
        searchController.dimsBackgroundDuringPresentation = false
        
        // Setup the Scope Bar
        tableView.tableHeaderView = searchController.searchBar
        
        books = [
            "Angels & Demons",
            "Old Man's War",
            "The Lock Artist",
            "HTML5",
            "Right Ho Jeeves",
            "The Code of the Wooster",
            "Thank You Jeeves",
            "The DaVinci Code",
            "The Silmarillion",
            "Syrup",
            "The Lost Symbol",
            "The Book of Lies",
            "Lamb",
            "Fool",
            "Incompetence",
            "Fat",
            "Colony",
            "Backwards, Red Dwarf",
            "The Grand Design",
            "The Book of Samson",
            "The Preservationist",
            "Fallen",
            "Monster 1959"
        ]
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
    
    // MARK: - Table View
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if searchController.isActive && searchController.searchBar.text != "" {
            return filteredBooks.count
        }
        return books.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        let item: NSMutableAttributedString
        
        if searchController.isActive && searchController.searchBar.text != "" {
            item = filteredBooks[indexPath.row]
        } else {
            item = NSMutableAttributedString(string: books[indexPath.row])
        }
        
        cell.textLabel!.attributedText = item
        
        return cell
    }
    
    func filterContentForSearchText(_ searchText: String) {
        let pattern = fuse.createPattern(from: searchText)
        
        typealias ItemTuple = (item: NSMutableAttributedString, score: Double)
        var results = [ItemTuple]()
        
        let boldAttrs = [
            NSFontAttributeName : UIFont.boldSystemFont(ofSize: 17),
            NSForegroundColorAttributeName: UIColor.blue
        ]
        
        books.forEach {
            // Search for the pattern in the book
            if let result = fuse.search(pattern, in: $0) {
                
                // if a result is found, do some text transformation so that
                // the substrings that are matched are bolded in the UI
                let ranges = result.ranges
                
                let attributedString = NSMutableAttributedString(string:"")
                var index: Int = 0
                var range = ranges[index]
                
                $0.characters.enumerated().forEach { (offset, character) in
                    let str = String(character)
                    
                    if offset > range.endIndex && index < ranges.count - 1 {
                        index += 1
                        range = ranges[index]
                    }
                    
                    if offset >= range.startIndex && offset <= range.endIndex {
                        attributedString.append(NSMutableAttributedString(string: str, attributes: boldAttrs))
                    } else {
                        attributedString.append(NSMutableAttributedString(string: str))
                    }
                }
                
                results.append((item: attributedString, score: result.score))
            }
        }
        
        filteredBooks = [NSMutableAttributedString]()
        
        // Sort the results by the score, and then add them into `filteredBooks`
        results.sorted { return $0.score < $1.score }.forEach { filteredBooks.append($0.item) }
        
        tableView.reloadData()
    }
    
}

extension ViewController: UISearchBarDelegate {
    // MARK: - UISearchBar Delegate
    func searchBar(_ searchBar: UISearchBar, selectedScopeButtonIndexDidChange selectedScope: Int) {
        filterContentForSearchText(searchBar.text!)
    }
}

extension ViewController: UISearchResultsUpdating {
    // MARK: - UISearchResultsUpdating Delegate
    func updateSearchResults(for searchController: UISearchController) {
        filterContentForSearchText(searchController.searchBar.text!)
    }
}
