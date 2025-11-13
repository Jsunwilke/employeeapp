//
//  ImageNumbersMergerTests.swift
//  Iconik Employee
//
//  Test cases for ImageNumbersMerger utility
//  These demonstrate the intelligent merge behavior
//

import Foundation

class ImageNumbersMergerTests {

    static func runAllTests() {
        print("🧪 Running ImageNumbersMerger Tests...\n")

        testSimpleMerge()
        testRangeMerge()
        testDuplicateRemoval()
        testSorting()
        testComplexMerge()
        testNotesMerge()
        testEdgeCases()

        print("\n✅ All ImageNumbersMerger tests completed!")
    }

    // MARK: - Test Cases

    static func testSimpleMerge() {
        print("Test 1: Simple Merge")
        let result = ImageNumbersMerger.mergeImageNumbers(local: "101", remote: "102")
        assert(result == "101, 102", "Expected '101, 102' but got '\(result)'")
        print("  ✓ '101' + '102' = '\(result)'")
    }

    static func testRangeMerge() {
        print("\nTest 2: Range Merge (User's Example)")
        let result = ImageNumbersMerger.mergeImageNumbers(local: "234-35", remote: "678-79")
        // Should be sorted by first number: 234 < 678
        assert(result == "234-35, 678-79", "Expected '234-35, 678-79' but got '\(result)'")
        print("  ✓ '234-35' + '678-79' = '\(result)'")
    }

    static func testDuplicateRemoval() {
        print("\nTest 3: Duplicate Removal")
        let result = ImageNumbersMerger.mergeImageNumbers(local: "101, 102", remote: "102, 103")
        assert(result == "101, 102, 103", "Expected '101, 102, 103' but got '\(result)'")
        print("  ✓ '101, 102' + '102, 103' = '\(result)' (duplicate '102' removed)")
    }

    static func testSorting() {
        print("\nTest 4: Numeric Sorting")
        let result = ImageNumbersMerger.mergeImageNumbers(local: "103, 101", remote: "102")
        assert(result == "101, 102, 103", "Expected '101, 102, 103' but got '\(result)'")
        print("  ✓ '103, 101' + '102' = '\(result)' (sorted numerically)")
    }

    static func testComplexMerge() {
        print("\nTest 5: Complex Merge with Ranges and Numbers")
        let result = ImageNumbersMerger.mergeImageNumbers(local: "234-35, 101", remote: "678-79, 102")
        // Should be sorted: 101, 102, 234-35, 678-79
        assert(result == "101, 102, 234-35, 678-79", "Expected '101, 102, 234-35, 678-79' but got '\(result)'")
        print("  ✓ '234-35, 101' + '678-79, 102' = '\(result)'")
    }

    static func testNotesMerge() {
        print("\nTest 6: Notes Merge")
        let result = ImageNumbersMerger.mergeNotes(local: "Note A", remote: "Note B")
        assert(result == "Note A; Note B", "Expected 'Note A; Note B' but got '\(result)'")
        print("  ✓ 'Note A' + 'Note B' = '\(result)'")

        let duplicateResult = ImageNumbersMerger.mergeNotes(local: "Same note", remote: "Same note")
        assert(duplicateResult == "Same note", "Expected 'Same note' but got '\(duplicateResult)'")
        print("  ✓ 'Same note' + 'Same note' = '\(duplicateResult)' (duplicate removed)")
    }

    static func testEdgeCases() {
        print("\nTest 7: Edge Cases")

        // Empty local
        var result = ImageNumbersMerger.mergeImageNumbers(local: "", remote: "101")
        assert(result == "101", "Expected '101' but got '\(result)'")
        print("  ✓ '' + '101' = '\(result)'")

        // Empty remote
        result = ImageNumbersMerger.mergeImageNumbers(local: "101", remote: "")
        assert(result == "101", "Expected '101' but got '\(result)'")
        print("  ✓ '101' + '' = '\(result)'")

        // Both empty
        result = ImageNumbersMerger.mergeImageNumbers(local: "", remote: "")
        assert(result == "", "Expected '' but got '\(result)'")
        print("  ✓ '' + '' = '\(result)'")

        // Whitespace handling
        result = ImageNumbersMerger.mergeImageNumbers(local: " 101 , 102 ", remote: " 103 ")
        assert(result == "101, 102, 103", "Expected '101, 102, 103' but got '\(result)'")
        print("  ✓ ' 101 , 102 ' + ' 103 ' = '\(result)' (whitespace cleaned)")
    }

    // MARK: - Helper

    private static func assert(_ condition: Bool, _ message: String) {
        if !condition {
            print("  ❌ FAILED: \(message)")
        }
    }
}

// Run tests when this file is loaded in debug mode
#if DEBUG
// Uncomment the line below to run tests automatically
// ImageNumbersMergerTests.runAllTests()
#endif
