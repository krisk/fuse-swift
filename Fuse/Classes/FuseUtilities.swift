//
//  FuseUtilities.swift
//  Pods
//
//  Created by Kirollos Risk on 5/2/17.
//
//

import Foundation

class FuseUtilities {
    /// Computes the score for a match with `e` errors and `x` location.
    ///
    /// - Parameter pattern: Pattern being sought.
    /// - Parameter errorCount: Number of errors in match.
    /// - Parameter matchLocation: Location of match.
    /// - Parameter loc: Expected location of match.
    /// - Parameter scoreTextLength: Coerced version of text's length.
    /// - Returns: Overall score for match (0.0 = good, 1.0 = bad).
    static func calculateScore(_ pattern: String, errorCount: Int, matchLocation: Int, loc: Int, distance: Int) -> Double {
        calculateScore(pattern.count, errorCount: errorCount, matchLocation: matchLocation, loc: loc, distance: distance)
    }

    /// Computes the score for a match with `e` errors and `x` location.
    ///
    /// - Parameter patternLength: Length of pattern being sought.
    /// - Parameter e: Number of errors in match.
    /// - Parameter x: Location of match.
    /// - Parameter loc: Expected location of match.
    /// - Parameter scoreTextLength: Coerced version of text's length.
    /// - Returns: Overall score for match (0.0 = good, 1.0 = bad).
    static func calculateScore(_ patternLength: Int, errorCount: Int, matchLocation: Int, loc: Int, distance: Int) -> Double {
        let accuracy = Double(errorCount) / Double(patternLength)
        let proximity = abs(matchLocation - loc)
        if distance == 0 {
            return Double(proximity != 0 ? 1 : accuracy)
        }
        return Double(accuracy) + (Double(proximity) / Double(distance))
    }

    /// Initializes the alphabet for the Bitap algorithm
    ///
    /// - Parameter pattern: The text to encode.
    /// - Returns: Hash of character locations.
    static func calculatePatternAlphabet(_ pattern: String) -> [Character: Int] {
        let len = pattern.count
        var mask = [Character: Int]()
        for (index, pattern) in pattern.enumerated() {
            mask[pattern] = (mask[pattern] ?? 0) | (1 << (len - index - 1))
        }
        return mask
    }

    /// Returns an array of `CountableClosedRange<Int>`, where each range represents a consecutive list of `1`s.
    ///
    ///     let arr = [0, 1, 1, 0, 1, 1, 1 ]
    ///     let ranges = findRanges(arr)
    ///     // [{startIndex 1, endIndex 2}, {startIndex 4, endIndex 6}
    ///
    /// - Parameter mask: A string representing the value to search for.
    ///
    /// - Returns: `CountableClosedRange<Int>` array.
    static func findRanges(_ mask: [Int]) -> [CountableClosedRange<Int>] {
        var ranges = [CountableClosedRange<Int>]()
        var start: Int = -1
        for (index, bit) in mask.enumerated() {
            if start == -1, bit == 1 {
                start = index
            }
            else if start != -1, bit == 0 {
                ranges.append(CountableClosedRange<Int>(start ..< index))
                start = -1
            }
        }
        if mask.last == 1 {
            ranges.append(CountableClosedRange<Int>(start ..< mask.count))
        }
        return ranges
    }
}
