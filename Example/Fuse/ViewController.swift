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
    var filteredBooks = [NSAttributedString]()
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
        let item: NSAttributedString
        
        if searchController.isActive && searchController.searchBar.text != "" {
            item = filteredBooks[indexPath.row]
        } else {
            item = NSAttributedString(string: books[indexPath.row])
        }
        
        cell.textLabel!.attributedText = item
        
        return cell
    }
    
    func filterContentForSearchText(_ searchText: String) {
        let boldAttrs = [
            NSAttributedString.Key.font : UIFont.boldSystemFont(ofSize: 17),
            NSAttributedString.Key.foregroundColor: UIColor.blue
        ]

        let results = fuse.search(searchText, in: books)

        filteredBooks = results.map { (index, _, matchedRanges) in
            let book = books[index]

            let attributedString = NSMutableAttributedString(string: book)
            matchedRanges
                .map(Range.init)
                .map(NSRange.init)
                .forEach {
                    attributedString.addAttributes(boldAttrs, range: $0)
                }

            return attributedString
        }
        
        tableView.reloadData()
    }
    
}

extension ViewController: UISearchBarDelegate {
    // MARK: - UISearchBar Delegate
    func searchBar(_ searchBar: UISearchBar, selectedScopeButtonIndexDidChange selectedScope: Int) {
        // TODO: can run this on a background queue, and then reload the tableview back on the main queue
        filterContentForSearchText(searchBar.text!)
    }
}

extension ViewController: UISearchResultsUpdating {
    // MARK: - UISearchResultsUpdating Delegate
    func updateSearchResults(for searchController: UISearchController) {
        filterContentForSearchText(searchController.searchBar.text!)
    }
}
