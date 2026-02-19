// BlueprintTests.swift — Tests for Blueprint, Field, DSL, and the examples

import XCTest
@testable import TinyTalk

final class BlueprintTests: XCTestCase {

    // MARK: - Invoice Example

    func testInvoiceInitialState() {
        let invoice = Invoice()
        XCTAssertEqual(invoice.amount, Number(0))
        XCTAssertEqual(invoice.status, "draft")
        XCTAssertEqual(invoice.approved, false)
    }

    func testInvoiceForgeSubmit() {
        let invoice = Invoice()
        // Set amount first (rules require positive amount)
        invoice._amount.wrappedValue = Number(100)

        let verdict = invoice.forge("submit")
        XCTAssertTrue(verdict.isCommit, "Submit should succeed")
        XCTAssertEqual(invoice.status, "submitted")
    }

    func testInvoiceForgeApprove() {
        let invoice = Invoice()
        invoice._amount.wrappedValue = Number(100)

        // Must submit first
        invoice.forge("submit")
        XCTAssertEqual(invoice.status, "submitted")

        // Then approve
        let verdict = invoice.forge("approve")
        XCTAssertTrue(verdict.isCommit, "Approve should succeed")
        XCTAssertEqual(invoice.status, "approved")
        XCTAssertTrue(invoice.approved)
    }

    func testInvoiceForgePay_Approved() {
        let invoice = Invoice()
        invoice._amount.wrappedValue = Number(15000)

        invoice.forge("submit")
        invoice.forge("approve")

        let verdict = invoice.forge("pay")
        XCTAssertTrue(verdict.isCommit, "Pay should succeed when approved")
        XCTAssertEqual(invoice.status, "paid")
    }

    func testInvoiceForgePay_NotApproved_HighAmount() {
        let invoice = Invoice()
        invoice._amount.wrappedValue = Number(15000)

        invoice.forge("submit")
        // Skip approve — go straight to pay

        let verdict = invoice.forge("pay")
        XCTAssertTrue(verdict.isFinfr, "Pay should fail without approval for high amounts")
        // Status should remain unchanged
        XCTAssertEqual(invoice.status, "submitted")
    }

    func testInvoiceUnknownForge() {
        let invoice = Invoice()
        let verdict = invoice.forge("nonexistent")
        XCTAssertTrue(verdict.isFinfr)
        XCTAssertEqual(verdict.witness?.reason, "No forge named \"nonexistent\" is defined")
    }

    func testInvoiceLedgerRecordsAllAttempts() {
        let invoice = Invoice()
        invoice._amount.wrappedValue = Number(100)

        invoice.forge("submit")
        invoice.forge("approve")
        invoice.forge("pay")

        // All three forges should be recorded
        XCTAssertEqual(invoice.ledger.count, 3)
        XCTAssertTrue(invoice.ledger[0].verdict.isCommit)
        XCTAssertTrue(invoice.ledger[1].verdict.isCommit)
        XCTAssertTrue(invoice.ledger[2].verdict.isCommit)
    }

    func testInvoiceAvailableForges() {
        let invoice = Invoice()
        let forges = invoice.availableForges
        XCTAssertTrue(forges.contains("submit"))
        XCTAssertTrue(forges.contains("approve"))
        XCTAssertTrue(forges.contains("pay"))
        XCTAssertTrue(forges.contains("set_amount"))
    }

    // MARK: - Field Property Wrapper

    func testFieldCommitAndRollback() {
        let field = Field<Number>(wrappedValue: Number(10))

        // Begin forge
        field.beginForge()
        XCTAssertEqual(field.committedValue, Number(10))

        // Write proposed value
        field.wrappedValue = Number(20)
        XCTAssertEqual(field.wrappedValue, Number(20))
        XCTAssertEqual(field.committedValue, Number(10))

        // Rollback
        field.rollback()
        XCTAssertEqual(field.wrappedValue, Number(10))
    }

    func testFieldCommit() {
        let field = Field<Number>(wrappedValue: Number(10))

        field.beginForge()
        field.wrappedValue = Number(20)

        field.commit()
        XCTAssertEqual(field.wrappedValue, Number(20))
        XCTAssertEqual(field.committedValue, Number(20))
    }

    func testFieldStateValues() {
        let field = Field<Number>(wrappedValue: Number(5))
        XCTAssertEqual(field.currentStateValue, 5.0, accuracy: 1e-10)

        field.beginForge()
        field.wrappedValue = Number(10)
        XCTAssertEqual(field.currentStateValue, 5.0, accuracy: 1e-10)
        XCTAssertEqual(field.proposedStateValue, 10.0, accuracy: 1e-10)
    }

    // MARK: - StatePath

    func testStatePathValidTransitions() {
        let path = StatePath("draft", "submitted", "approved", "paid")

        XCTAssertTrue(path.isValidTransition(from: "draft", to: "submitted"))
        XCTAssertTrue(path.isValidTransition(from: "draft", to: "approved"))
        XCTAssertTrue(path.isValidTransition(from: "submitted", to: "paid"))
        XCTAssertFalse(path.isValidTransition(from: "paid", to: "draft"))
        XCTAssertFalse(path.isValidTransition(from: "approved", to: "submitted"))
    }

    func testStatePathNextStep() {
        let path = StatePath("draft", "submitted", "approved", "paid")

        XCTAssertTrue(path.isNextStep(from: "draft", to: "submitted"))
        XCTAssertTrue(path.isNextStep(from: "submitted", to: "approved"))
        XCTAssertFalse(path.isNextStep(from: "draft", to: "approved"))
        XCTAssertFalse(path.isNextStep(from: "draft", to: "paid"))
    }

    // MARK: - Condition and Rule DSL

    func testWhenCondition() {
        let c = when(true)
        XCTAssertTrue(c.check())

        let c2 = when(false)
        XCTAssertFalse(c2.check())
    }

    func testRuleConstruction() {
        let r = rule("test rule") {
            when(true, label: "always true")
        }
        XCTAssertEqual(r.name, "test rule")
        XCTAssertTrue(r.isSatisfied())
    }

    func testRuleWithFailingCondition() {
        let r = rule("failing rule") {
            when(false, label: "always false")
        }
        XCTAssertFalse(r.isSatisfied())
        XCTAssertNotNil(r.firstViolation())
    }

    // MARK: - Navigator Example (Section 10)

    func testNavigatorSafeMove() {
        let nav = Navigator(x: 1, y: 1)

        // Move to (1, 5) — should be safe (avoids all obstacles)
        let verdict = nav.moveTo(x: 1, y: 5)
        XCTAssertTrue(verdict.isCommit, "Direct move to (1,5) should be safe")
        XCTAssertEqual(nav.x, Number(1))
        XCTAssertEqual(nav.y, Number(5))
    }

    func testNavigatorBlockedByRectangle() {
        let nav = Navigator(x: 1, y: 1)

        // Straight line to (9,5) passes through rectangle [2,4]×[1,3]
        let verdict = nav.moveTo(x: 9, y: 5)
        XCTAssertTrue(verdict.isFinfr, "Straight line through rectangle should be blocked")
        // Position should remain unchanged
        XCTAssertEqual(nav.x, Number(1))
        XCTAssertEqual(nav.y, Number(1))
    }

    func testNavigatorArcingTrajectory() {
        let nav = Navigator(x: 1, y: 1)

        // Use the adjusted proposal from Section 10.5
        let verdict = nav.moveAlong(
            p1: (2, 4.5),
            p2: (6, 5.5),
            to: (9, 5)
        )
        XCTAssertTrue(verdict.isCommit, "Arcing trajectory should succeed")
        XCTAssertEqual(nav.x, Number(9))
        XCTAssertEqual(nav.y, Number(5))
    }

    func testNavigatorBoundaryViolation() {
        let nav = Navigator(x: 1, y: 1)

        // Try to move outside the boundary [0,10]×[0,6]
        let verdict = nav.moveTo(x: -1, y: 1)
        XCTAssertTrue(verdict.isFinfr, "Moving outside boundary should be blocked")
    }

    func testNavigatorCircleAvoidance() {
        let nav = Navigator(x: 6, y: 4)

        // Try to move through the circle at (7,4) radius 1
        let verdict = nav.moveTo(x: 8, y: 4)
        XCTAssertTrue(verdict.isFinfr, "Moving through circle should be blocked")
    }

    func testNavigatorLedgerRecords() {
        let nav = Navigator(x: 1, y: 1)

        nav.moveTo(x: 1, y: 5)  // Should succeed
        nav.moveTo(x: 9, y: 5)  // Should fail (through rectangle from (1,5))

        XCTAssertEqual(nav.ledger.count, 2)
        XCTAssertTrue(nav.ledger[0].verdict.isCommit)
    }
}
