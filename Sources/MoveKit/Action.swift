import Foundation

/// Every window action. The raw value is the preferences key for its shortcut and matches Rectangle's names,
/// so `move://execute-action?name=<kebab-case>` takes the same names as `rectangle://`.
nonisolated public enum Action: String, CaseIterable, Sendable {
    // Halves
    case leftHalf, rightHalf, centerHalf, topHalf, bottomHalf
    // Corners
    case topLeft, topRight, bottomLeft, bottomRight
    // Thirds
    case firstThird, centerThird, lastThird, firstTwoThirds, centerTwoThirds, lastTwoThirds
    // Fourths
    case firstFourth, secondFourth, thirdFourth, lastFourth, firstThreeFourths, centerThreeFourths, lastThreeFourths
    // Maximize & center
    case maximize, almostMaximize, maximizeHeight, center, centerProminently, specified, restore
    // Size
    case larger, smaller, largerWidth, smallerWidth, largerHeight, smallerHeight
    case halveHeightUp, halveHeightDown, halveWidthLeft, halveWidthRight
    case doubleHeightUp, doubleHeightDown, doubleWidthLeft, doubleWidthRight
    // Move to edge
    case moveLeft, moveRight, moveUp, moveDown
    // Displays
    case nextDisplay, previousDisplay
    case displayOne, displayTwo, displayThree, displayFour, displayFive, displaySix, displaySeven, displayEight, displayNine
    // Vertical thirds (always rows)
    case topVerticalThird, middleVerticalThird, bottomVerticalThird, topVerticalTwoThirds, bottomVerticalTwoThirds
    // Sixths
    case topLeftSixth, topCenterSixth, topRightSixth, bottomLeftSixth, bottomCenterSixth, bottomRightSixth
    // Corner thirds (⅔ wide, half high)
    case topLeftThird, topRightThird, bottomLeftThird, bottomRightThird
    // Ninths
    case topLeftNinth, topCenterNinth, topRightNinth, middleLeftNinth, middleCenterNinth, middleRightNinth
    case bottomLeftNinth, bottomCenterNinth, bottomRightNinth
    // Eighths
    case topLeftEighth, topCenterLeftEighth, topCenterRightEighth, topRightEighth
    case bottomLeftEighth, bottomCenterLeftEighth, bottomCenterRightEighth, bottomRightEighth
    // Twelfths
    case topLeftTwelfth, topCenterLeftTwelfth, topCenterRightTwelfth, topRightTwelfth
    case middleLeftTwelfth, middleCenterLeftTwelfth, middleCenterRightTwelfth, middleRightTwelfth
    case bottomLeftTwelfth, bottomCenterLeftTwelfth, bottomCenterRightTwelfth, bottomRightTwelfth
    // Sixteenths
    case topLeftSixteenth, topCenterLeftSixteenth, topCenterRightSixteenth, topRightSixteenth
    case upperMiddleLeftSixteenth, upperMiddleCenterLeftSixteenth, upperMiddleCenterRightSixteenth, upperMiddleRightSixteenth
    case lowerMiddleLeftSixteenth, lowerMiddleCenterLeftSixteenth, lowerMiddleCenterRightSixteenth, lowerMiddleRightSixteenth
    case bottomLeftSixteenth, bottomCenterLeftSixteenth, bottomCenterRightSixteenth, bottomRightSixteenth
    // Vertical sixths & eighths (full-height columns)
    case firstVerticalSixth, secondVerticalSixth, thirdVerticalSixth, fourthVerticalSixth, fifthVerticalSixth, lastVerticalSixth
    case firstVerticalEighth, secondVerticalEighth, thirdVerticalEighth, fourthVerticalEighth
    case fifthVerticalEighth, sixthVerticalEighth, seventhVerticalEighth, lastVerticalEighth

    /// `left-half`, `first-two-thirds`, `top-left-sixth` …
    public var urlName: String {
        var out = ""
        for ch in rawValue {
            if ch.isUppercase { out += "-" + ch.lowercased() } else { out.append(ch) }
        }
        return out
    }

    public init?(urlName: String) {
        guard let a = Action.allCases.first(where: { $0.urlName == urlName || $0.rawValue == urlName }) else { return nil }
        self = a
    }

    /// "Left Half", "Top Center Left Eighth", "Display 3".
    public var title: String {
        switch self {
        case .almostMaximize: return "Almost Maximize"
        case .maximizeHeight: return "Maximize Height"
        case .centerProminently: return "Center Prominently"
        case .specified: return "Specified Size"
        case .nextDisplay: return "Next Display"
        case .previousDisplay: return "Previous Display"
        default: break
        }
        if let n = displayIndex { return "Display \(n + 1)" }
        var words: [String] = []
        var cur = ""
        for ch in rawValue {
            if ch.isUppercase, !cur.isEmpty { words.append(cur); cur = "" }
            cur.append(ch)
        }
        words.append(cur)
        return words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    public var displayIndex: Int? {
        let all: [Action] = [.displayOne, .displayTwo, .displayThree, .displayFour, .displayFive,
                             .displaySix, .displaySeven, .displayEight, .displayNine]
        return all.firstIndex(of: self)
    }

    public enum Group: String, CaseIterable, Sendable {
        case halves = "Halves", corners = "Corners", thirds = "Thirds", fourths = "Fourths",
             maximize = "Maximize & Center", size = "Size", move = "Move to Edge", displays = "Displays",
             verticalThirds = "Vertical Thirds", sixths = "Sixths", cornerThirds = "Corner Thirds",
             ninths = "Ninths", eighths = "Eighths", twelfths = "Twelfths", sixteenths = "Sixteenths",
             columns = "Columns"
    }

    public var group: Group {
        switch self {
        case .leftHalf, .rightHalf, .centerHalf, .topHalf, .bottomHalf: return .halves
        case .topLeft, .topRight, .bottomLeft, .bottomRight: return .corners
        case .firstThird, .centerThird, .lastThird, .firstTwoThirds, .centerTwoThirds, .lastTwoThirds: return .thirds
        case .firstFourth, .secondFourth, .thirdFourth, .lastFourth, .firstThreeFourths, .centerThreeFourths,
             .lastThreeFourths: return .fourths
        case .maximize, .almostMaximize, .maximizeHeight, .center, .centerProminently, .specified, .restore: return .maximize
        case .larger, .smaller, .largerWidth, .smallerWidth, .largerHeight, .smallerHeight, .halveHeightUp,
             .halveHeightDown, .halveWidthLeft, .halveWidthRight, .doubleHeightUp, .doubleHeightDown,
             .doubleWidthLeft, .doubleWidthRight: return .size
        case .moveLeft, .moveRight, .moveUp, .moveDown: return .move
        case .nextDisplay, .previousDisplay, .displayOne, .displayTwo, .displayThree, .displayFour, .displayFive,
             .displaySix, .displaySeven, .displayEight, .displayNine: return .displays
        case .topVerticalThird, .middleVerticalThird, .bottomVerticalThird, .topVerticalTwoThirds,
             .bottomVerticalTwoThirds: return .verticalThirds
        case .topLeftSixth, .topCenterSixth, .topRightSixth, .bottomLeftSixth, .bottomCenterSixth,
             .bottomRightSixth: return .sixths
        case .topLeftThird, .topRightThird, .bottomLeftThird, .bottomRightThird: return .cornerThirds
        case .topLeftNinth, .topCenterNinth, .topRightNinth, .middleLeftNinth, .middleCenterNinth, .middleRightNinth,
             .bottomLeftNinth, .bottomCenterNinth, .bottomRightNinth: return .ninths
        case .topLeftEighth, .topCenterLeftEighth, .topCenterRightEighth, .topRightEighth, .bottomLeftEighth,
             .bottomCenterLeftEighth, .bottomCenterRightEighth, .bottomRightEighth: return .eighths
        case .topLeftTwelfth, .topCenterLeftTwelfth, .topCenterRightTwelfth, .topRightTwelfth, .middleLeftTwelfth,
             .middleCenterLeftTwelfth, .middleCenterRightTwelfth, .middleRightTwelfth, .bottomLeftTwelfth,
             .bottomCenterLeftTwelfth, .bottomCenterRightTwelfth, .bottomRightTwelfth: return .twelfths
        case .topLeftSixteenth, .topCenterLeftSixteenth, .topCenterRightSixteenth, .topRightSixteenth,
             .upperMiddleLeftSixteenth, .upperMiddleCenterLeftSixteenth, .upperMiddleCenterRightSixteenth,
             .upperMiddleRightSixteenth, .lowerMiddleLeftSixteenth, .lowerMiddleCenterLeftSixteenth,
             .lowerMiddleCenterRightSixteenth, .lowerMiddleRightSixteenth, .bottomLeftSixteenth,
             .bottomCenterLeftSixteenth, .bottomCenterRightSixteenth, .bottomRightSixteenth: return .sixteenths
        case .firstVerticalSixth, .secondVerticalSixth, .thirdVerticalSixth, .fourthVerticalSixth, .fifthVerticalSixth,
             .lastVerticalSixth, .firstVerticalEighth, .secondVerticalEighth, .thirdVerticalEighth,
             .fourthVerticalEighth, .fifthVerticalEighth, .sixthVerticalEighth, .seventhVerticalEighth,
             .lastVerticalEighth: return .columns
        }
    }

    /// Size actions keep the window where it is; moves keep its size.
    public var resizes: Bool {
        switch self {
        case .center, .centerProminently, .nextDisplay, .previousDisplay, .moveLeft, .moveRight, .moveUp, .moveDown:
            return false
        default: return displayIndex == nil
        }
    }

    /// Doubling may push past the screen edge on purpose.
    var mayExtendPastScreen: Bool {
        [.doubleHeightUp, .doubleHeightDown, .doubleWidthLeft, .doubleWidthRight].contains(self)
    }

    /// Which dimensions get the window gap.
    var gaps: (h: Bool, v: Bool) {
        switch self {
        case .maximize: return (true, true)
        case .maximizeHeight: return (false, true)
        case .almostMaximize, .center, .centerProminently, .specified, .restore, .larger, .smaller, .largerWidth,
             .smallerWidth, .largerHeight, .smallerHeight, .moveLeft, .moveRight, .moveUp, .moveDown,
             .nextDisplay, .previousDisplay:
            return (false, false)
        default: return displayIndex == nil ? (true, true) : (false, false)
        }
    }
}
