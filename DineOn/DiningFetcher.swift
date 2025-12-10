//
//  DiningFetcher.swift
//  DineOn
//
//  Created by Om Chachad on 10/17/25.
//

import Foundation
import WebKit
import Combine

class DiningFetcher: ObservableObject {
    static let shared = DiningFetcher()
    
    @Published var diningMenu: DiningMenu? = nil
    @Published var isLoading: Bool = false
    
    private let cacheFileName = "diningMenuCache.json"
    
    private var cacheFileURL: URL {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsDirectory.appendingPathComponent(cacheFileName)
    }
    
    private init() {
        loadCachedMenu()
    }
    
    let page = WebPage()
    
    /// Loads the cached menu from disk if available
    private func loadCachedMenu() {
        guard FileManager.default.fileExists(atPath: cacheFileURL.path) else {
            print("📦 No cached menu found")
            return
        }
        
        do {
            let data = try Data(contentsOf: cacheFileURL)
            let decoder = JSONDecoder()
            let cachedMenu = try decoder.decode(DiningMenu.self, from: data)
            
            // Check if the cached menu is still valid
            if isMenuValid(cachedMenu) {
                self.diningMenu = cachedMenu
                print("📦 Loaded valid cached menu with dates:", cachedMenu.availableDates)
            } else {
                print("📦 Cached menu expired, clearing cache")
                clearCache()
            }
        } catch {
            print("❌ Failed to load cached menu:", error)
            clearCache()
        }
    }
    
    /// Saves the current menu to disk
    private func saveCachedMenu() {
        guard let menu = diningMenu else { return }
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(menu)
            try data.write(to: cacheFileURL, options: .atomic)
            print("💾 Menu cached successfully to:", cacheFileURL.path)
        } catch {
            print("❌ Failed to cache menu:", error)
        }
    }
    
    /// Clears the cached menu from disk
    private func clearCache() {
        do {
            if FileManager.default.fileExists(atPath: cacheFileURL.path) {
                try FileManager.default.removeItem(at: cacheFileURL)
                print("🗑️ Cache cleared")
            }
        } catch {
            print("❌ Failed to clear cache:", error)
        }
    }
    
    /// Checks if the provided menu is still valid for today
    private func isMenuValid(_ menu: DiningMenu) -> Bool {
        let today = Calendar.current.startOfDay(for: Date())
        let todayString = formatDateString(today)
        
        // Check if today's date is in the available dates
        return menu.availableDates.contains(todayString)
    }
    
    /// Formats a date to YYYY-MM-DD string
    private func formatDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    
    /// Fetches the dining menu, using cache if valid
    func fetchDiningMenu(forceRefresh: Bool = false) {
        // If not forcing refresh and menu is still valid, don't fetch
        if !forceRefresh, let menu = diningMenu, isMenuValid(menu) {
            print("📦 Using cached menu - still valid for today")
            return
        }
        
        // If we get here, either there's no cache or it's expired
        if diningMenu != nil && !isMenuValid(diningMenu!) {
            print("🔄 Cached menu expired, fetching new data...")
        } else if !forceRefresh {
            print("🔄 No valid cache, fetching menu data...")
        } else {
            print("🔄 Force refresh requested, fetching new data...")
        }
        
        let urlString = URL(
            string: "https://hospitality.usc.edu/dining-hall-menus/"
        )!
        
        var request = URLRequest(url: urlString)
        request.attribution = .user
        
        page.load(urlString)
        
        Task {
            isLoading = true
            while page.isLoading {
                try? await Task.sleep(for: .milliseconds(100))
            }
            
            let js = #"""
            console.log("🍽️ Starting USC Dining Hall WEEKLY menu extraction...");

            const wait = (ms) => new Promise(r => setTimeout(r, ms));

            function getCurrentWeekDates() {
              const today = new Date();
              const day = today.getDay();
              const start = new Date(today);
              start.setDate(today.getDate() - day);
              const end = new Date(start);
              end.setDate(start.getDate() + 7);
              const dates = [];
              for (let d = new Date(start); d <= end; d.setDate(d.getDate() + 1)) {
                const yyyy = d.getFullYear();
                const mm = String(d.getMonth() + 1).padStart(2, '0');
                const dd = String(d.getDate()).padStart(2, '0');
                dates.push(`${yyyy}-${mm}-${dd}`);
              }
              return dates;
            }

            const disclaimerKeywords = [
              "may contain", "contains traces", "processed in a facility", "manufactured in a facility",
              "shared equipment", "cross contamination", "nuts and peanuts are used", "nuts are used",
              "peanuts are used", "not analyzed"
            ].map(s => s.toLowerCase());
            const nutRegex = /\b(peanut|peanuts|nut|nuts|tree[- ]?nut|almond|walnut|cashew|pecan)\b/i;

            function isDisclaimerText(text) {
              if (!text) return false;
              const t = text.trim().toLowerCase();
              return disclaimerKeywords.some(k => t.includes(k)) ||
                     (nutRegex.test(t) && /(used|may|contain)/.test(t)) ||
                     /^\*.*\*$/.test(text.trim());
            }

            const timeHeaderRegex = /\b(opens|starts|closes)\s+at\b/i;
            const isTimeHeader = (text) => timeHeaderRegex.test(text.trim());

            function looksLikeHeader(text) {
              if (!text) return false;
              if (isDisclaimerText(text) || isTimeHeader(text)) return false;
              const words = text.trim().split(/\s+/);
              if (words.length <= 6 && /^[A-Z0-9 '&\-/()]+$/.test(text.trim())) return true;
              const letters = text.replace(/[^A-Za-z]/g, "");
              if (letters.length > 0 && text === text.toUpperCase() && words.length <= 5) return true;
              return false;
            }

            function safeParseArray(str) {
              if (!str) return [];
              try { return JSON.parse(str); } catch {
                const match = str.match(/"([^"]+)"/g);
                return match ? match.map(m => m.replace(/"/g, "")) : [];
              }
            }

            function extractCurrentMenu() {
              const venueTitle = document.querySelector('.js-venue-title')?.textContent.trim() || 'Unknown Venue';
              const menus = {};

              document.querySelectorAll('.meal-container').forEach(meal => {
                const mealName = meal.querySelector('.h4')?.textContent.trim() || 'Unknown Meal';
                menus[mealName] = {};

                meal.querySelectorAll('.station').forEach(station => {
                  const stationName = station.querySelector('.title')?.textContent.trim() || 'Unnamed Station';
                  const subtitle = station.querySelector('.subtitle')?.textContent.trim() || null;

                  const items = [];
                  let currentHeader = subtitle
                    ? { name: subtitle, type: "header", items: [], disclaimers: [] }
                    : null;
                  if (currentHeader) items.push(currentHeader);

                  let currentTimeHeader = null;

                  station.querySelectorAll('.js-menu-item').forEach(li => {
                    const text = li.childNodes[0]?.textContent.trim() || li.textContent.trim();
                    const allergens = safeParseArray(li.dataset.allergens || '[]');
                    const preferences = safeParseArray(li.dataset.preferences || '[]');
                    const hasLabels = allergens.length > 0 || preferences.length > 0;

                    if (isDisclaimerText(text)) {
                      const d = text;
                      if (currentTimeHeader) {
                        currentTimeHeader.disclaimers = currentTimeHeader.disclaimers || [];
                        currentTimeHeader.disclaimers.push(d);
                      } else if (currentHeader) {
                        currentHeader.disclaimers.push(d);
                      }
                      return;
                    }

                    if (isTimeHeader(text)) {
                      currentTimeHeader = { name: text, type: "time-header", items: [], disclaimers: [] };
                      if (currentHeader) currentHeader.items.push(currentTimeHeader);
                      else items.push(currentTimeHeader);
                      return;
                    }

                    if (!hasLabels && looksLikeHeader(text)) {
                      currentHeader = { name: text, type: "header", items: [], disclaimers: [] };
                      items.push(currentHeader);
                      currentTimeHeader = null;
                      return;
                    }

                    const itemObj = { name: text, type: "item", allergens, preferences, disclaimers: [] };
                    if (currentTimeHeader) currentTimeHeader.items.push(itemObj);
                    else if (currentHeader) currentHeader.items.push(itemObj);
                    else items.push(itemObj);
                  });

                  menus[mealName][stationName] = items;
                });
              });

              return { venue: venueTitle, menu: menus };
            }

            const dateInput = document.querySelector('#date');
            if (!dateInput) throw new Error("❌ Date input not found.");

            const buttons = {
              evk: document.querySelector('button[data-value="evk"]'),
              parkside: document.querySelector('button[data-value="parkside"]'),
              village: document.querySelector('button[data-value="university-village"]'),
            };

            const allMenus = {};
            const weekDates = getCurrentWeekDates();

            for (const dateStr of weekDates) {
              console.log(`📅 Fetching ${dateStr}...`);
              dateInput.value = dateStr;
              dateInput.dispatchEvent(new Event('input', { bubbles: true }));
              dateInput.dispatchEvent(new Event('change', { bubbles: true }));
              await wait(700);

              allMenus[dateStr] = {};

              for (const [key, btn] of Object.entries(buttons)) {
                if (!btn) continue;
                btn.click();
                btn.dispatchEvent(new Event('click', { bubbles: true }));
                btn.dispatchEvent(new Event('change', { bubbles: true }));
                await wait(800);

                const { venue, menu } = extractCurrentMenu();
                allMenus[dateStr][venue] = menu;
                console.log(`✅ ${venue} done for ${dateStr}`);
              }
            }

            console.log("🍴 Weekly extraction complete.");
            return allMenus;
            """#

            do {
                
                let result = try await page.callJavaScript(js)
                do {
                    self.diningMenu = try DiningMenuParser.parse(from: result as Any)
                    
                    // Save to disk after successful fetch
                    self.saveCachedMenu()
                    
                    if let firstDate = self.diningMenu?.availableDates.first {
                        print("✅ Menu fetched and cached. Available dates:", self.diningMenu?.availableDates ?? [])
                        let venues = self.diningMenu?.venues(for: firstDate) ?? []
                        print("Venues on \(firstDate):", venues)
                    }
                } catch {
                    print("❌ Parsing failed:", error)
                }
            } catch {
                print("❌ Error executing JavaScript: \(error)")
            }
            
            isLoading = false
        }
    }
    
    /// Refreshes the menu for a specific date (expects "yyyy-MM-dd").
    /// This will fetch only the requested date across all venues, update the in-memory
    /// `diningMenu.data[dateString]` and immediately save the cache to disk.
    func refreshMenu(for dateString: String) {
        Task {
            isLoading = true
            defer { isLoading = false }
            
            print("🔄 Force-refreshing menus for date:", dateString)
            
            let url = URL(string: "https://hospitality.usc.edu/dining-hall-menus/")!
            page.load(url)
            
            // wait for the page to finish loading
            while page.isLoading {
                try? await Task.sleep(for: .milliseconds(120))
            }
            
            // JavaScript that extracts the menu for a single date (buttons iterate venues)
            var js = #"""
            (function() {
              const wait = (ms) => new Promise(r => setTimeout(r, ms));
              
              function safeParseArray(str) {
                if (!str) return [];
                try { return JSON.parse(str); } catch {
                  const match = str.match(/"([^"]+)"/g);
                  return match ? match.map(m => m.replace(/"/g, "")) : [];
                }
              }
              
              const disclaimerKeywords = [
                "may contain", "contains traces", "processed in a facility", "manufactured in a facility",
                "shared equipment", "cross contamination", "nuts and peanuts are used", "nuts are used",
                "peanuts are used", "not analyzed"
              ].map(s => s.toLowerCase());
              
              const nutRegex = /\b(peanut|peanuts|nut|nuts|tree[- ]?nut|almond|walnut|cashew|pecan)\b/i;
              function isDisclaimerText(text) {
                if (!text) return false;
                const t = text.trim().toLowerCase();
                return disclaimerKeywords.some(k => t.includes(k)) ||
                       (nutRegex.test(t) && /(used|may|contain)/.test(t)) ||
                       /^\*.*\*$/.test(text.trim());
              }
              
              const timeHeaderRegex = /\b(opens|starts|closes)\s+at\b/i;
              const isTimeHeader = (text) => timeHeaderRegex.test(text.trim());
              
              function looksLikeHeader(text) {
                if (!text) return false;
                if (isDisclaimerText(text) || isTimeHeader(text)) return false;
                const words = text.trim().split(/\s+/);
                if (words.length <= 6 && /^[A-Z0-9 '&\-/()]+$/.test(text.trim())) return true;
                const letters = text.replace(/[^A-Za-z]/g, "");
                if (letters.length > 0 && text === text.toUpperCase() && words.length <= 5) return true;
                return false;
              }
              
              function extractMenuForVenue() {
                const venueTitle = document.querySelector('.js-venue-title')?.textContent.trim() || 'Unknown Venue';
                const menus = {};

                document.querySelectorAll('.meal-container').forEach(meal => {
                  const mealName = meal.querySelector('.h4')?.textContent.trim() || 'Unknown Meal';
                  menus[mealName] = {};

                  meal.querySelectorAll('.station').forEach(station => {
                    const stationName = station.querySelector('.title')?.textContent.trim() || 'Unnamed Station';
                    const subtitle = station.querySelector('.subtitle')?.textContent.trim() || null;

                    const items = [];
                    let currentHeader = subtitle ? { name: subtitle, type: "header", items: [], disclaimers: [] } : null;
                    if (currentHeader) items.push(currentHeader);

                    let currentTimeHeader = null;

                    station.querySelectorAll('.js-menu-item').forEach(li => {
                      const text = li.childNodes[0]?.textContent.trim() || li.textContent.trim();
                      const allergens = safeParseArray(li.dataset.allergens || '[]');
                      const preferences = safeParseArray(li.dataset.preferences || '[]');
                      const hasLabels = allergens.length > 0 || preferences.length > 0;

                      if (isDisclaimerText(text)) {
                        const d = text;
                        if (currentTimeHeader) {
                          currentTimeHeader.disclaimers = currentTimeHeader.disclaimers || [];
                          currentTimeHeader.disclaimers.push(d);
                        } else if (currentHeader) {
                          currentHeader.disclaimers.push(d);
                        }
                        return;
                      }

                      if (isTimeHeader(text)) {
                        currentTimeHeader = { name: text, type: "time-header", items: [], disclaimers: [] };
                        if (currentHeader) currentHeader.items.push(currentTimeHeader);
                        else items.push(currentTimeHeader);
                        return;
                      }

                      if (!hasLabels && looksLikeHeader(text)) {
                        currentHeader = { name: text, type: "header", items: [], disclaimers: [] };
                        items.push(currentHeader);
                        currentTimeHeader = null;
                        return;
                      }

                      const itemObj = { name: text, type: "item", allergens, preferences, disclaimers: [] };
                      if (currentTimeHeader) currentTimeHeader.items.push(itemObj);
                      else if (currentHeader) currentHeader.items.push(itemObj);
                      else items.push(itemObj);
                    });

                    menus[mealName][stationName] = items;
                  });
                });

                return { venue: venueTitle, menu: menus };
              }

              const dateInput = document.querySelector('#date');
              if (!dateInput) throw new Error("Date input not found");

              // PLACEHOLDER replaced by Swift with the requested date string
              dateInput.value = PLACEHOLDER_DATE;
              dateInput.dispatchEvent(new Event('input', { bubbles: true }));
              dateInput.dispatchEvent(new Event('change', { bubbles: true }));

              const buttons = {
                evk: document.querySelector('button[data-value="evk"]'),
                parkside: document.querySelector('button[data-value="parkside"]'),
                village: document.querySelector('button[data-value="university-village"]'),
              };

              const result = {};

              // iterate available venue buttons and collect their menus
              const buttonEntries = Object.entries(buttons);
              const run = async () => {
                for (const [key, btn] of buttonEntries) {
                  if (!btn) continue;
                  btn.click();
                  btn.dispatchEvent(new Event('click', { bubbles: true }));
                  btn.dispatchEvent(new Event('change', { bubbles: true }));
                  await wait(700);
                  const { venue, menu } = extractMenuForVenue();
                  result[venue] = menu;
                }
                return result;
              };

              return run();
            })();
            """# // end js
            
            // Inject the requested date string safely (wrap with quotes)
            js = js.replacingOccurrences(of: "PLACEHOLDER_DATE", with: "\"\(dateString)\"")
            
            do {
                let raw = try await page.callJavaScript(js)
                
                guard let venueMenus = raw as? [String: Any] else {
                    print("❌ JavaScript returned unexpected shape for date \(dateString)")
                    return
                }
                
                // Parse only the single-date dictionary using your existing parser
                let singleDateDict: [String: Any] = [dateString: venueMenus]
                let parsed = try DiningMenuParser.parse(from: singleDateDict)
                
                if diningMenu == nil {
                    // no cache yet — replace entire menu with fetched one
                    diningMenu = parsed
                } else {
                    // update only requested date's entry
                    diningMenu!.data[dateString] = parsed.data[dateString]
                }
                
                // Persist immediately
                saveCachedMenu()
                print("✅ Refresh for \(dateString) complete. Cache updated.")
                
            } catch {
                print("❌ refreshMenu(for:) failed for \(dateString):", error)
            }
        }
    }
}
