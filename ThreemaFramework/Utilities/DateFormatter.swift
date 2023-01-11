//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2020-2022 Threema GmbH
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License, version 3,
// as published by the Free Software Foundation.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

import Foundation

/// Format and convert dates and time
///
/// All methods are `static`, no initialization needed.
///
/// Formatters are cached to improve performance. Call `forceReinitialize()` to reset them.
///
/// - Note: All examples of the formatted strings reflect **February 1, 2020 at 1:14:15 PM GMT+1**
public class DateFormatter: NSObject {
    
    // MARK: - Formats provided by the system
    
    /// Localized short date and time string
    ///
    /// Examples in multiple locales:
    /// - 2/1/20, 1:14 PM (en_US)
    /// - 01.02.20, 13:14 (de_DE)
    /// - 01.02.20 13:14 (fr_CH)
    ///
    /// - Parameter date: Date to format
    /// - Returns: Localized short date and time string or empty string if `date` is nil
    @objc
    public static func shortStyleDateTime(_ date: Date?) -> String {
        guard let date = date else {
            return ""
        }
        
        if shortDateTimeDateFormatter == nil {
            shortDateTimeDateFormatter = dateFormatterWith(date: .short, andTime: .short)
        }
        
        return shortDateTimeDateFormatter!.string(from: date)
    }
    
    /// Localized short date and medium time (with seconds) string
    ///
    /// Examples in multiple locales:
    /// - 2/1/20, 1:14:15 PM (en_US)
    /// - 01.02.20, 13:14:15 (de_DE)
    /// - 01.02.20 13:14:15 (fr_CH)
    ///
    /// - Parameter date: Date to format
    /// - Returns: Localized short date and medium time (with seconds) string or empty string if `date` is nil
    @objc
    public static func shortStyleDateTimeSeconds(_ date: Date?) -> String {
        guard let date = date else {
            return ""
        }
        
        if shortDateMediumTimeDateFormatter == nil {
            shortDateMediumTimeDateFormatter = dateFormatterWith(date: .short, andTime: .medium)
        }
        
        return shortDateMediumTimeDateFormatter!.string(from: date)
    }
    
    /// Localized medium date and time (with seconds) string
    ///
    /// Examples in multiple locales:
    /// - Feb 1, 2020 at 1:14:15 PM (en_US)
    /// - 01.02.2020, 13:14:15 (de_DE)
    /// - 1 févr. 2020 à 13:14:15 (fr_CH)
    ///
    /// - Parameter date: Date to format
    /// - Returns: Localized medium date and time (with seconds) string or empty string if `date` is nil
    @objc
    public static func mediumStyleDateTime(_ date: Date?) -> String {
        guard let date = date else {
            return ""
        }
        
        if mediumDateTimeDateFormatter == nil {
            mediumDateTimeDateFormatter = dateFormatterWith(date: .medium, andTime: .medium)
        }
        
        return mediumDateTimeDateFormatter!.string(from: date)
    }
    
    /// Localized medium date and short time (no seconds) string
    ///
    /// Examples in multiple locales:
    /// - Feb 1, 2020 at 1:14 PM (en_US)
    /// - 01.02.2020, 13:14 (de_DE)
    /// - 1 févr. 2020 à 13:14 (fr_CH)
    ///
    /// - Parameter date: Date to format
    /// - Returns: Localized medium date and short time (no seconds) string
    public static func mediumStyleDateShortStyleTime(_ date: Date) -> String {
        if mediumDateShortTimeDateFormatter == nil {
            mediumDateShortTimeDateFormatter = dateFormatterWith(date: .medium, andTime: .short)
        }
        
        return mediumDateShortTimeDateFormatter!.string(from: date)
    }
    
    /// Localized long date and time (with time zone) string
    ///
    /// Examples in multiple locales:
    /// - February 1, 2020 at 1:14:15 PM GMT+1 (en_US)
    /// - 1. Februar 2020 um 13:14:15 MEZ (de_DE)
    /// - 1 février 2020 à 13:14:15 UTC+1 (fr_CH)
    ///
    /// - Parameter date: Date to format
    /// - Returns: Localized long date and time (with time zone) string or empty string if `date` is nil
    @objc
    public static func longStyleDateTime(_ date: Date?) -> String {
        guard let date = date else {
            return ""
        }
        
        if longDateTimeDateFormatter == nil {
            longDateTimeDateFormatter = dateFormatterWith(date: .long, andTime: .long)
        }
        
        return longDateTimeDateFormatter!.string(from: date)
    }
    
    /// Localized short time (no seconds) string
    ///
    /// e.g. 1:14 PM or 13:14
    ///
    /// - Parameter date: Date to format
    /// - Returns: Localized short time (no seconds) string or empty string if `date` is nil
    @objc
    public static func shortStyleTimeNoDate(_ date: Date?) -> String {
        guard let date = date else {
            return ""
        }
        
        if shortTimeDateFormatter == nil {
            shortTimeDateFormatter = dateFormatterWith(date: .none, andTime: .short)
        }
        
        return shortTimeDateFormatter!.string(from: date)
    }
    
    /// Localized relative medium date string
    ///
    /// - Note: Marked as private, because it's only used internally
    ///
    /// Examples in multiple locales:
    /// - Today, Yesterday, .., Feb 1, 2020 (en_US)
    /// - Heute, Gestern, Vorgestern, ..., 01.02.2020 (de_DE)
    /// - aujourd’hui, hier, avant-hier, ..., 1 févr. 2020 (fr_CH)
    ///
    /// - Parameter date: Date to format
    /// - Returns: Localized relative medium date string
    private static func relativeMediumStyleDate(_ date: Date) -> String {
        if relativeMediumDateDateFormatter == nil {
            relativeMediumDateDateFormatter = dateFormatterWith(date: .medium, andTime: .none)
            relativeMediumDateDateFormatter?.doesRelativeDateFormatting = true
        }
        
        return relativeMediumDateDateFormatter!.string(from: date)
    }
    
    /// Localized relative long date and short time (no seconds) string
    ///
    /// Examples in multiple locales:
    /// - Tomorrow at 1:14 PM, Today at 1:14 PM, Yesterday at 1:14 PM, .., Feb 1, 2020 at 1:14 PM (en_US)
    /// - Morgen, 13:14, Heute, 13:14, Gestern, 13:14, Vorgestern, 13:14, ..., 01.02.2020, 13:14 (de_DE)
    /// - aujourd’hui à 13:14, hier à 13:14, avant-hier à 13:14, ..., 1 févr. 2020 à 13:14 (fr_CH)
    ///
    /// - Parameter date: Date to format
    /// - Returns: Localized relative long date and short time (no seconds) string
    @objc
    public static func relativeLongStyleDateShortStyleTime(_ date: Date) -> String {
        if relativeLongStyleDateShortStyleTimeFormatter == nil {
            relativeLongStyleDateShortStyleTimeFormatter = dateFormatterWith(date: .medium, andTime: .short)
            relativeLongStyleDateShortStyleTimeFormatter?.doesRelativeDateFormatting = true
        }
        
        return relativeLongStyleDateShortStyleTimeFormatter!.string(from: date)
    }
    
    // MARK: - Custom formats
    
    /// Localized short day, month and year string
    ///
    /// Examples in multiple locales:
    /// - 2/1/2020 (en_US)
    /// - 1.2.2020 (de_DE)
    /// - 01.02.2020 (fr_CH)
    ///
    /// - Parameter date: Date to format
    /// - Returns: Localized short day, month and year string or empty string if `date` is nil
    @objc
    public static func getShortDate(_ date: Date?) -> String {
        guard let date = date else {
            return ""
        }
        
        if shortDayMonthAndYearDateFormatter == nil {
            shortDayMonthAndYearDateFormatter = dateFormatter(for: "d M y")
        }
        
        return shortDayMonthAndYearDateFormatter!.string(from: date)
    }
    
    /// Localized short weekday, medium day, medium month and long year string
    ///
    /// Examples in multiple locales:
    /// - Sat, Feb 01, 2020 (en_US)
    /// - Sa. 01. Feb. 2020 (de_DE)
    /// - sam. 01 févr. 2020 (fr_CH)
    ///
    /// - Parameter date: Date to format
    /// - Returns: Localized short weekday, medium day, medium month and full year string or empty string if `date` is nil
    @objc
    public static func getDayMonthAndYear(_ date: Date?) -> String {
        guard let date = date else {
            return ""
        }
        
        if mediumWeekdayDayMonthAndYearDateFormatter == nil {
            mediumWeekdayDayMonthAndYearDateFormatter = dateFormatter(for: "EE dd MMM yyyy")
        }
        
        return mediumWeekdayDayMonthAndYearDateFormatter!.string(from: date)
    }
    
    /// Localized short weekday, medium day and medium month
    ///
    /// - Note: Marked as private, because it's only used internally
    ///
    /// Examples in multiple locales:
    /// - Sat, Feb 01 (en_US)
    /// - Sa. 01. Feb. (de_DE)
    /// - sam. 01 févr. (fr_CH)
    ///
    /// - Parameter date: Date to format
    /// - Returns: Localized short weekday, medium day and medium month
    @objc
    private static func mediumWeekdayDayAndMonth(_ date: Date) -> String {
        if mediumWeekdayDayAndMonthDateFormatter == nil {
            mediumWeekdayDayAndMonthDateFormatter = dateFormatter(for: "EE dd MMM")
        }
        
        return mediumWeekdayDayAndMonthDateFormatter!.string(from: date)
    }
    
    /// Localized  weekday
    ///
    /// - Note: Marked as private, because it's only used internally
    ///
    /// Examples in multiple locales:
    /// - Saturday
    /// - Samstag
    /// - Samedi
    ///
    /// - Parameter date: Date to format
    /// - Returns: Localized short weekday, medium day and medium month
    @objc
    private static func weekday(_ date: Date) -> String {
        if weekdayFormatter == nil {
            weekdayFormatter = dateFormatter(for: "EEEE")
        }
        
        return weekdayFormatter!.string(from: date)
    }
    
    /// Localized short weekday, medium day, medium month and long year string including short time
    ///
    /// Examples in multiple locales:
    /// - Sat, Feb 01, 2020, 1:14 PM (en_US)
    /// - Sa. 01. Feb. 2020, 13:14 (de_DE)
    /// - sam. 01 févr. 2020 à 13:14 (fr_CH)
    ///
    /// - Parameter date: Date to format
    /// - Returns: Localized short weekday, medium day, medium month and long year string including short time or empty string if `date` is nil
    @objc
    public static func getFullDate(for date: Date?) -> String {
        guard let date = date else {
            return ""
        }
        
        if mediumWeekdayDayMonthYearAndTimeDateFormatter == nil {
            mediumWeekdayDayMonthYearAndTimeDateFormatter = dateFormatter(for: "j:mm EE dd MMM yyyy")
        }
        
        return mediumWeekdayDayMonthYearAndTimeDateFormatter!.string(from: date)
    }
    
    /// Long year string
    ///
    /// - Parameter date: Date to format
    /// - Returns: Long year string or empty string if `date` is nil
    @objc
    public static func getYear(for date: Date?) -> String {
        guard let date = date else {
            return ""
        }
        
        let dateFormatter = dateFormatter(for: "yyyy")
        return dateFormatter.string(from: date)
    }

    // MARK: - To `Date` converter
    
    /// Convert localized date string into into `Date`
    ///
    /// This is the reverse function of `getDayMonthAndYear(_:)`
    ///
    /// Examples for localized inputs:
    /// - Sat, Feb 01, 2020 (en_US)
    /// - Sa. 01. Feb. 2020 (de_DE)
    /// - sam. 01 févr. 2020 (fr_CH)
    ///
    /// - Parameter dateString: Date string in current locale
    /// - Returns: Parsed date or nil if parsing failed
    @objc
    public static func getDateFromDayMonthAndYearDateString(_ dateString: String) -> Date? {
        let setMediumWeekdayDayMonthAndYearDateFormatter = {
            mediumWeekdayDayMonthAndYearDateFormatter = dateFormatter(for: "EE dd MMM yyyy")
        }
        
        if mediumWeekdayDayMonthAndYearDateFormatter == nil {
            setMediumWeekdayDayMonthAndYearDateFormatter()
        }
        
        if let date = mediumWeekdayDayMonthAndYearDateFormatter!.date(from: dateString) {
            return date
        }
        
        // Try to recover from locale change by resetting the formatter
        locale = Locale.current
        setMediumWeekdayDayMonthAndYearDateFormatter()
        
        if let date = mediumWeekdayDayMonthAndYearDateFormatter!.date(from: dateString) {
            return date
        }
        
        return nil
    }
    
    /// Convert localized date and time string into `Date`
    ///
    /// This is the reverse function of `getFullDate(for:)`
    ///
    /// Examples for localized inputs:
    /// - Sat, Feb 01, 2020, 1:14 PM (en_US)
    /// - Sa. 01. Feb. 2020, 13:14 (de_DE)
    /// - sam. 01 févr. 2020 à 13:14 (fr_CH)
    ///
    /// - Parameter dateString: Date string with time in current locale
    /// - Returns: Parsed date or nil if parsing failed
    @objc
    public static func getDateFromFullDateString(_ dateString: String) -> Date? {
        let setMediumWeekdayDayMonthYearAndTimeDateFormatter = {
            mediumWeekdayDayMonthYearAndTimeDateFormatter = dateFormatter(for: "j:mm EE dd MMM yyyy")
        }
        
        if mediumWeekdayDayMonthYearAndTimeDateFormatter == nil {
            setMediumWeekdayDayMonthYearAndTimeDateFormatter()
        }
        
        if let date = mediumWeekdayDayMonthYearAndTimeDateFormatter!.date(from: dateString) {
            return date
        }
        
        // Try to recover from locale change by resetting the formatter
        locale = Locale.current
        setMediumWeekdayDayMonthYearAndTimeDateFormatter()
        
        if let date = mediumWeekdayDayMonthYearAndTimeDateFormatter!.date(from: dateString) {
            return date
        }
        
        return nil
    }
    
    /// Get date with time set to provided 24h time
    ///
    /// - Parameter timeString: Time string of 24h time (e.g. 1:30 or 18:53)
    /// - Returns: Date with time set to provided string in current calendar
    public static func getDate(from timeString: String) -> Date? {
        let (_, hours, minutes) = split(timeString: timeString)
        
        var dateComponents = DateComponents()
        dateComponents.hour = hours
        dateComponents.minute = minutes
        
        return Calendar.current.date(from: dateComponents)
    }
    
    // MARK: - Relative custom formats
    
    /// Localized relative date
    ///
    /// Localized text for today and yesterday, weekday, day and month for the rest of this calendar year. For previous years it also shows the year.
    ///
    /// Examples in multiple locales:
    /// - Today, Yesterday, Sat, Feb 01, ..., Tue, Dec 31, 2019, Sat, Feb 01 2019 (en_US)
    /// - Heute, Gestern, Sa. 01. Feb., ..., Di. 31. Dez. 2019, Sa. 01. Feb. 2019 (de_DE)
    /// - aujourd’hui, hier, sam. 01 févr., ..., mar. 31 déc. 2019, sam. 01 févr. 2019  (fr_CH)
    ///
    /// - Parameter date: Date to format
    /// - Returns: Localized relative date or empty string if `date` is nil
    @objc
    public static func relativeMediumDate(for date: Date?) -> String {
        guard let date = date else {
            return ""
        }
        
        if isDateInTodayOrYesterday(date) {
            return relativeMediumStyleDate(date)
        }
        else if isDateInLastSixDays(date) {
            return weekday(date)
        }
        else if isDateInThisCalendarYear(date) {
            return mediumWeekdayDayAndMonth(date)
        }
        else {
            return getDayMonthAndYear(date)
        }
    }
    
    /// Localized relative time or date
    ///
    /// If `date` is in today it will show the time. Otherwise a relative date like `relativeMediumDate(for:)`.
    ///
    /// - Parameter date: Date to format
    /// - Returns: Localized relative time or date
    public static func relativeTimeTodayAndMediumDateOtherwise(for date: Date) -> String {
        if isDateInToday(date) {
            return shortStyleTimeNoDate(date)
        }
        else {
            return relativeMediumDate(for: date)
        }
    }
    
    // MARK: - Accessibility formats
    
    /// Localized date and time for accessibility
    ///
    /// Examples in multiple locales:
    /// - February 1, 2020, 1:14 PM (en_US)
    /// - 1. Februar 2020, 13:14 (de_DE)
    /// - 1 février 2020 à 13:14 (fr_CH)
    ///
    /// - Parameter date: Date to format
    /// - Returns: Localized date and time for accessibility or empty string if `date` is nil
    @objc
    public static func accessibilityDateTime(_ date: Date?) -> String {
        guard let date = date else {
            return ""
        }
        
        if accessibilityDateTimeDateFormatter == nil {
            accessibilityDateTimeDateFormatter = dateFormatter(for: "j:mm d MMMM yyyy")
        }
        
        return accessibilityDateTimeDateFormatter!.string(from: date)
    }
    
    /// Localized date and time for accessibility using relative dates for recent days (e.g. today, yesterday)
    ///
    /// Examples in multiple locales:
    /// - February 1, 2020 at 1:14 PM (en_US)
    /// - 1. Februar 2020 um 13:14 (de_DE)
    /// - 1 février 2020 à 13:14 (fr_CH)
    ///
    /// - Parameter date: Date to format
    /// - Returns: Localized date and time for accessibility using relative dates for recent days (e.g. today, yesterday) or empty string if `date` is nil
    @objc
    public static func accessibilityRelativeDayTime(_ date: Date?) -> String {
        guard let date = date else {
            return ""
        }
        
        if accessibilityRelativeDateTimeDateFormatter == nil {
            accessibilityRelativeDateTimeDateFormatter = dateFormatterWith(date: .long, andTime: .short)
            accessibilityRelativeDateTimeDateFormatter?.doesRelativeDateFormatting = true
        }
        
        return accessibilityRelativeDateTimeDateFormatter!.string(from: date)
    }
    
    // MARK: - Locale independent time formatter
    
    /// Date independent of locale
    ///
    /// Example: 20200102-131415
    ///
    /// - Parameter date: Date to format
    /// - Returns: Formatted date or empty string if `date` is nil
    @objc
    public static func getDateForWeb(_ date: Date?) -> String {
        guard let date = date else {
            return ""
        }
        
        if webDateFormatter == nil {
            webDateFormatter = Foundation.DateFormatter()
            // Always use this locale for locale independent formats (see https://nsdateformatter.com)
            webDateFormatter?.locale = Locale(identifier: "en_US_POSIX")
            webDateFormatter?.dateFormat = "yyyyMMdd-HHmmss"
        }
        
        return webDateFormatter!.string(from: date)
    }
    
    @objc
    public static func getNowDateString() -> String {
        if nowDateFormatter == nil {
            nowDateFormatter = Foundation.DateFormatter()
            nowDateFormatter?.locale = Locale(identifier: "en_US_POSIX")
            nowDateFormatter?.dateFormat = "yyyyMMddHHmm"
        }
        
        return nowDateFormatter!.string(from: Date())
    }
    
    // MARK: - Time conversion
    
    /// Format seconds into time string
    ///
    /// This might be replaced by `DateComponentsFormatter` in the future for better localization. It requires that
    /// `totalSeconds` is not required as an inverse function.
    ///
    /// - Parameter totalSeconds: Seconds to transform
    /// - Returns: String of format "01:02:03" with hour omitted if it's zero
    @objc
    public static func timeFormatted(_ totalSeconds: Int) -> String {
        let seconds = totalSeconds % 60
        let minutes = (totalSeconds / 60) % 60
        let hours = totalSeconds / 60 / 60
        
        if hours == 0 {
            return String(format: "%02d:%02d", minutes, seconds)
        }
        else {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
    }
    
    /// Format seconds into time string showing a negative time if `totalSeconds` is negative
    ///
    /// This might be replaced by `DateComponentsFormatter` in the future for better localization. It requires that
    /// `totalSeconds` is not required as an inverse function.
    ///
    /// - Parameter totalSeconds: Seconds to transform
    /// - Returns: String of format "01:02:03" with hour omitted if it's zero
    @objc
    public static func maybeNegativeTimeFormatted(_ totalSeconds: Int) -> String {
        let negativeOrNothing = totalSeconds < 0 ? "-" : ""
        
        let totalSeconds = abs(totalSeconds)
        let seconds = totalSeconds % 60
        let minutes = (totalSeconds / 60) % 60
        let hours = totalSeconds / 60 / 60
        
        if hours == 0 {
            return String(format: "%@%02d:%02d", negativeOrNothing, minutes, seconds)
        }
        else {
            return String(format: "%@%02d:%02d:%02d", negativeOrNothing, hours, minutes, seconds)
        }
    }
    
    /// Converts time string into seconds
    ///
    /// - Parameter timeFormatted: Time string with format "01:02:03" where the hour can be omitted
    /// - Returns: Number of seconds
    public static func totalSeconds(_ timeFormatted: String) -> Int {
        let (hours, minutes, seconds) = split(timeString: timeFormatted)
        
        return seconds + (minutes * 60) + (hours * 60 * 60)
    }
    
    // MARK: - Caching
    
    // Does it still make sense to cache formatters in 2020?
    // Probably, yes (http://jordansmith.io/performant-date-parsing/).
    
    /// Reset all cached date formatters and reset to current locale
    public static func forceReinitialize() {
        shortDateTimeDateFormatter = nil
        shortDateMediumTimeDateFormatter = nil
        mediumDateTimeDateFormatter = nil
        mediumDateShortTimeDateFormatter = nil
        longDateTimeDateFormatter = nil
        shortTimeDateFormatter = nil
        relativeMediumDateDateFormatter = nil
        relativeLongStyleDateShortStyleTimeFormatter = nil
        
        shortDayMonthAndYearDateFormatter = nil
        mediumWeekdayDayMonthAndYearDateFormatter = nil
        mediumWeekdayDayAndMonthDateFormatter = nil
        longWeekdayDayMonthAndYearDateFormatter = nil
        mediumWeekdayDayMonthYearAndTimeDateFormatter = nil
        
        accessibilityDateTimeDateFormatter = nil
        accessibilityRelativeDateTimeDateFormatter = nil
        
        webDateFormatter = nil
        
        locale = Locale.current
    }
    
    // Note: If you add a new property reset it in `forceReinitialize()`.
    
    private static var shortDateTimeDateFormatter: Foundation.DateFormatter?
    private static var shortDateMediumTimeDateFormatter: Foundation.DateFormatter?
    private static var mediumDateTimeDateFormatter: Foundation.DateFormatter?
    private static var mediumDateShortTimeDateFormatter: Foundation.DateFormatter?
    private static var longDateTimeDateFormatter: Foundation.DateFormatter?
    private static var shortTimeDateFormatter: Foundation.DateFormatter?
    private static var relativeMediumDateDateFormatter: Foundation.DateFormatter?
    private static var relativeLongStyleDateShortStyleTimeFormatter: Foundation.DateFormatter?
    
    private static var shortDayMonthAndYearDateFormatter: Foundation.DateFormatter?
    private static var mediumWeekdayDayMonthAndYearDateFormatter: Foundation.DateFormatter?
    private static var weekdayFormatter: Foundation.DateFormatter?
    private static var mediumWeekdayDayAndMonthDateFormatter: Foundation.DateFormatter?
    private static var longWeekdayDayMonthAndYearDateFormatter: Foundation.DateFormatter?
    private static var mediumWeekdayDayMonthYearAndTimeDateFormatter: Foundation.DateFormatter?
    
    private static var accessibilityDateTimeDateFormatter: Foundation.DateFormatter?
    private static var accessibilityRelativeDateTimeDateFormatter: Foundation.DateFormatter?
    
    private static var webDateFormatter: Foundation.DateFormatter?
    private static var nowDateFormatter: Foundation.DateFormatter?
    
    // MARK: - Private helper functions
    
    private static func dateFormatterWith(
        date dateStyle: Foundation.DateFormatter.Style,
        andTime timeStyle: Foundation.DateFormatter.Style
    ) -> Foundation.DateFormatter {
        
        let dateFormatter = Foundation.DateFormatter()
        dateFormatter.locale = DateFormatter.locale
        
        dateFormatter.dateStyle = dateStyle
        dateFormatter.timeStyle = timeStyle
        
        return dateFormatter
    }
    
    private static func dateFormatter(for format: String) -> Foundation.DateFormatter {
        
        let dateFormatter = Foundation.DateFormatter()
        dateFormatter.locale = DateFormatter.locale
        
        dateFormatter.setLocalizedDateFormatFromTemplate(format)
        
        return dateFormatter
    }
        
    /// Split a time string separated by `:`
    ///
    /// - Parameter timeString: Time string (e.g. "hours:minutes:seconds" or "hours:minutes")
    /// - Returns: Split components
    private static func split(timeString: String) -> (first: Int, middle: Int, last: Int) {
        // Convert components to `Int` or set to 0 otherwise
        let components: [Int] = timeString.split(separator: ":").map { Int($0) ?? 0 }
        
        var last = 0
        var middle = 0
        var first = 0
        
        switch components.count {
        case 1:
            last = components.first!
        case 2:
            last = components[components.endIndex - 1]
            middle = components[components.endIndex - 2]
        case 3:
            last = components[components.endIndex - 1]
            middle = components[components.endIndex - 2]
            first = components[components.endIndex - 3]
        default:
            // no-op
            break
        }
        
        return (first, middle, last)
    }
    
    // MARK: - Private relative date helper
    
    /// Checks if `date` is in today
    ///
    /// - Parameter date: Date to check
    /// - Returns: `true` if the date is in today, `false` otherwise
    private static func isDateInToday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }
    
    /// Checks if `date` is in today or yesterday
    ///
    /// - Parameter date: Date to check
    /// - Returns: `true` if the date is in today or yesterday, `false` otherwise
    private static func isDateInTodayOrYesterday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date) || Calendar.current.isDateInYesterday(date)
    }
    
    /// Checks if `date` is in this calendar year
    ///
    /// - Parameter date: Date to check
    /// - Returns: `true` if the date is in this calendar year, `false` otherwise
    private static func isDateInThisCalendarYear(_ date: Date) -> Bool {
        var dateComponents = Calendar.current.dateComponents([.year], from: Date())
        
        dateComponents.second = -1
        
        guard let lastNewYearsEveJustBeforeMidnight = Calendar.current.date(from: dateComponents) else {
            return false
        }
        
        return date > lastNewYearsEveJustBeforeMidnight
    }
    
    /// Checks if `date` is in last six days
    ///
    /// i.e. if today is _Wednesday_ this function returns `true` for all dates up to and including last _Thursday_
    ///
    /// - Parameter date: Date to check
    /// - Returns: `false` if the date is in last 6 days, or not determinable in the current calendar, otherwise `true`
    private static func isDateInLastSixDays(_ date: Date) -> Bool {
        var dateComponents = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        
        guard let dayComponent = dateComponents.day else {
            return false
        }
        
        dateComponents.day = dayComponent - 6
        
        guard let aSevenDaysAgoMidnight = Calendar.current.date(from: dateComponents) else {
            return false
        }
        
        return date > aSevenDaysAgoMidnight
    }
    
    // MARK: - Helper for testing
    
    /// Only reassign this value for testing
    static var locale = Locale.current
}
