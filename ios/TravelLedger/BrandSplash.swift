import SwiftUI
import WebKit

/// The KUØ WORKS 杰構 opening animation (2.3 s), shown once when the app starts, with
/// "Design by Archie Kuo" underneath. The artwork is the brand's own SVG and timing script, played in a
/// web view so it matches the brand sheet exactly; the paths are outlines, so nothing is downloaded.
struct BrandSplash: UIViewRepresentable {
    /// Called once the page is drawn and the animation has started.
    var onStart: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(onStart: onStart) }

    func makeUIView(context: Context) -> WKWebView {
        let web = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear
        web.scrollView.isScrollEnabled = false
        web.isUserInteractionEnabled = false
        web.navigationDelegate = context.coordinator
        web.loadHTMLString(Self.html, baseURL: nil)
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onStart: () -> Void
        init(onStart: @escaping () -> Void) { self.onStart = onStart }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { onStart() }
    }

    /// Paper behind the animation (the brand sheet's --paper; also the launch screen colour), so nothing
    /// flashes before the page draws.
    static let paper = Color("LaunchPaper")

    /// How long the splash stays once the animation has started: its 2.3 s plus a short hold.
    static let duration: Duration = .milliseconds(2800)
    /// If the page never reports that it loaded, the app still appears after this long.
    static let giveUp: Duration = .seconds(5)

    static let html = #"""
<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover,user-scalable=no">
<style>
:root{--paper:#F5F5F3;--ink:#111111;--concrete:#8A8A88;color-scheme:light dark}
@media (prefers-color-scheme: dark){:root{--paper:#121212;--ink:#EDEDEA}}
html,body{height:100%;margin:0;background:var(--paper);color:var(--ink);overflow:hidden;-webkit-user-select:none}
body{display:flex;flex-direction:column;align-items:center;justify-content:center}
#splash{width:min(92vw,620px);height:auto;display:block;color:currentColor}
#splash .en path,#splash .zh path,#splash #sub>path{fill:currentColor}
#splash .en,#splash .zh{transform-box:view-box}
#splash .en{opacity:0}
#splash .zh{opacity:1}
#splash #sub{opacity:0}
#splash #seal{stroke-dasharray:1;stroke-dashoffset:1}
#credit{margin-top:14px;font:400 12px -apple-system,sans-serif;letter-spacing:.14em;color:var(--concrete);opacity:0;animation:credit .35s cubic-bezier(.16,1,.3,1) 1.9s both}
@keyframes credit{from{opacity:0;transform:translateY(4px)}to{opacity:1;transform:none}}
@media (prefers-reduced-motion: reduce){#credit{animation:none;opacity:1}}
</style></head><body>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="206 150 588 150" id="splash" role="img" aria-label="KUØ WORKS 杰構工作室 開啟動畫"><g class="en" style="transform:translate(246.39px,222.4px)"><path d="M5.12 -44.8V0H10.56V-44.8ZM28.16 -44.8 8.9 -23.68 29.12 0H35.84L15.49 -23.81L34.88 -44.8Z"/></g><g class="en" style="transform:translate(292.79px,222.4px)"><path d="M4.8 -44.8V-14.72Q4.8 -11.39 5.86 -8.58Q6.91 -5.76 8.93 -3.71Q10.94 -1.66 13.76 -0.51Q16.58 0.64 20.03 0.64Q23.49 0.64 26.3 -0.51Q29.12 -1.66 31.14 -3.71Q33.15 -5.76 34.21 -8.58Q35.26 -11.39 35.26 -14.72V-44.8H29.82V-14.72Q29.82 -10.11 27.33 -7.3Q24.83 -4.48 20.03 -4.48Q15.23 -4.48 12.74 -7.3Q10.24 -10.11 10.24 -14.72V-44.8Z"/></g><g class="en" style="transform:translate(343.09px,222.4px)"><path d="M2.56 -22.4a22.94 22.94 0 1 0 45.88 0a22.94 22.94 0 1 0 -45.88 0ZM7.89 -22.4a17.61 17.61 0 1 1 35.21 0a17.61 17.61 0 1 1 -35.21 0ZM11.25 4.62L43.53 -47.05L39.75 -49.42L7.46 2.25Z"/></g><g class="en" style="transform:translate(433.77px,222.4px)"><path d="M44.99 -11.84 31.68 -47.04 18.62 -11.84 6.72 -44.8H0.64L18.24 2.24L31.68 -32.58L45.12 2.24L62.72 -44.8H56.64Z"/></g><g class="en" style="transform:translate(507.37px,222.4px)"><path d="M8.32 -22.4Q8.32 -27.46 10.53 -31.42Q12.74 -35.39 16.58 -37.7Q20.42 -40 25.28 -40Q30.21 -40 34.02 -37.7Q37.82 -35.39 40.03 -31.42Q42.24 -27.46 42.24 -22.4Q42.24 -17.34 40.03 -13.38Q37.82 -9.41 34.02 -7.1Q30.21 -4.8 25.28 -4.8Q20.42 -4.8 16.58 -7.1Q12.74 -9.41 10.53 -13.38Q8.32 -17.34 8.32 -22.4ZM2.56 -22.4Q2.56 -17.54 4.26 -13.31Q5.95 -9.09 9.02 -5.98Q12.1 -2.88 16.26 -1.12Q20.42 0.64 25.28 0.64Q30.21 0.64 34.34 -1.12Q38.46 -2.88 41.54 -5.98Q44.61 -9.09 46.3 -13.31Q48 -17.54 48 -22.4Q48 -27.33 46.3 -31.52Q44.61 -35.71 41.54 -38.82Q38.46 -41.92 34.34 -43.68Q30.21 -45.44 25.28 -45.44Q20.42 -45.44 16.26 -43.68Q12.1 -41.92 9.02 -38.82Q5.95 -35.71 4.26 -31.52Q2.56 -27.33 2.56 -22.4Z"/></g><g class="en" style="transform:translate(568.17px,222.4px)"><path d="M13.12 -22.08 28.48 0H35.2L19.2 -22.08ZM5.12 -44.8V0H10.56V-44.8ZM8.13 -40H17.28Q20.16 -40 22.37 -38.98Q24.58 -37.95 25.82 -36.03Q27.07 -34.11 27.07 -31.36Q27.07 -28.61 25.82 -26.69Q24.58 -24.77 22.37 -23.74Q20.16 -22.72 17.28 -22.72H8.13V-17.92H17.28Q21.63 -17.92 25.06 -19.55Q28.48 -21.18 30.5 -24.22Q32.51 -27.26 32.51 -31.36Q32.51 -35.52 30.5 -38.53Q28.48 -41.54 25.06 -43.17Q21.63 -44.8 17.28 -44.8H8.13Z"/></g><g class="en" style="transform:translate(614.25px,222.4px)"><path d="M5.12 -44.8V0H10.56V-44.8ZM28.16 -44.8 8.9 -23.68 29.12 0H35.84L15.49 -23.81L34.88 -44.8Z"/></g><g class="en" style="transform:translate(660.65px,222.4px)"><path d="M6.78 -13.57 2.43 -10.62Q3.9 -7.68 6.24 -5.09Q8.58 -2.5 11.68 -0.93Q14.78 0.64 18.43 0.64Q21.12 0.64 23.58 -0.26Q26.05 -1.15 28 -2.82Q29.95 -4.48 31.07 -6.85Q32.19 -9.22 32.19 -12.16Q32.19 -15.23 31.1 -17.44Q30.02 -19.65 28.32 -21.22Q26.62 -22.78 24.64 -23.81Q22.66 -24.83 20.86 -25.47Q16.96 -26.82 14.69 -28.19Q12.42 -29.57 11.46 -31.14Q10.5 -32.7 10.5 -34.56Q10.5 -36.74 12.16 -38.5Q13.82 -40.26 17.47 -40.26Q20.1 -40.26 21.92 -39.23Q23.74 -38.21 25.02 -36.61Q26.3 -35.01 27.14 -33.34L31.81 -36.03Q30.72 -38.4 28.8 -40.54Q26.88 -42.69 24.16 -44.06Q21.44 -45.44 17.79 -45.44Q14.02 -45.44 11.07 -43.94Q8.13 -42.43 6.46 -39.81Q4.8 -37.18 4.8 -33.86Q4.8 -30.78 5.98 -28.67Q7.17 -26.56 9.02 -25.12Q10.88 -23.68 12.93 -22.75Q14.98 -21.82 16.64 -21.25Q19.2 -20.35 21.47 -19.23Q23.74 -18.11 25.15 -16.32Q26.56 -14.53 26.56 -11.52Q26.56 -8.45 24.38 -6.46Q22.21 -4.48 18.62 -4.48Q15.94 -4.48 13.82 -5.63Q11.71 -6.78 10.02 -8.83Q8.32 -10.88 6.78 -13.57Z"/></g><g class="zh" id="zh0" style="transform:translate(326px,225.2px)"><path d="M31.74 -36.3Q33 -35.52 35.04 -34.11Q37.08 -32.7 39.57 -30.93Q42.06 -29.16 44.67 -27.27Q47.28 -25.38 49.71 -23.64Q52.14 -21.9 53.97 -20.52Q55.8 -19.14 56.7 -18.42L54.24 -14.46Q53.16 -15.42 51.27 -16.95Q49.38 -18.48 47.07 -20.34Q44.76 -22.2 42.27 -24.18Q39.78 -26.16 37.38 -27.99Q34.98 -29.82 32.97 -31.35Q30.96 -32.88 29.58 -33.84ZM27.66 -50.4H32.34V-12.6H27.66ZM4.44 -41.1H55.5V-36.78H4.44ZM25.08 -38.94 28.68 -37.56Q26.22 -32.64 22.62 -28.05Q19.02 -23.46 14.76 -19.77Q10.5 -16.08 6.12 -13.62Q5.76 -14.22 5.19 -14.94Q4.62 -15.66 4.05 -16.32Q3.48 -16.98 2.94 -17.46Q7.26 -19.5 11.49 -22.86Q15.72 -26.22 19.26 -30.39Q22.8 -34.56 25.08 -38.94ZM20.34 -7.8 24.3 -8.58Q25.08 -6.78 25.74 -4.68Q26.4 -2.58 26.94 -0.66Q27.48 1.26 27.72 2.7L23.52 3.78Q23.28 2.28 22.8 0.3Q22.32 -1.68 21.69 -3.81Q21.06 -5.94 20.34 -7.8ZM32.94 -7.8 36.96 -8.76Q37.92 -7.02 38.85 -4.98Q39.78 -2.94 40.53 -0.99Q41.28 0.96 41.7 2.4L37.38 3.6Q37.02 2.16 36.33 0.18Q35.64 -1.8 34.74 -3.9Q33.84 -6 32.94 -7.8ZM44.94 -8.28 48.9 -9.9Q50.52 -7.98 52.14 -5.67Q53.76 -3.36 55.08 -1.11Q56.4 1.14 57.06 2.94L52.92 4.8Q52.26 3 50.97 0.72Q49.68 -1.56 48.12 -3.93Q46.56 -6.3 44.94 -8.28ZM10.74 -9.6 14.94 -8.52Q13.68 -4.92 11.73 -1.29Q9.78 2.34 7.38 4.8L3.3 3Q5.52 0.84 7.53 -2.64Q9.54 -6.12 10.74 -9.6Z"/></g><g class="zh" id="zh1" style="transform:translate(398px,225.2px)"><path d="M25.02 -38.16H55.5V-34.86H25.02ZM22.44 -30.78H57.54V-27.36H22.44ZM21.36 -8.58H58.26V-5.04H21.36ZM27.66 -16.2H51.9V-12.96H27.66ZM23.88 -45.48H56.34V-42.12H23.88ZM30.78 -50.4H34.98V-29.1H30.78ZM37.62 -28.68H41.76V-7.08H37.62ZM44.64 -50.4H48.84V-29.22H44.64ZM25.44 -23.76H51.9V-20.4H29.58V4.62H25.44ZM50.22 -23.76H54.42V0Q54.42 1.68 53.97 2.58Q53.52 3.48 52.38 3.96Q51.12 4.38 49.11 4.5Q47.1 4.62 44.16 4.62Q44.04 3.84 43.65 2.76Q43.26 1.68 42.84 0.9Q45 0.96 46.8 0.99Q48.6 1.02 49.14 0.96Q50.22 0.9 50.22 0ZM3.12 -37.38H22.62V-33.18H3.12ZM11.52 -50.4H15.66V4.74H11.52ZM11.4 -34.86 14.22 -33.96Q13.5 -30.36 12.45 -26.52Q11.4 -22.68 10.08 -18.96Q8.76 -15.24 7.26 -12.06Q5.76 -8.88 4.14 -6.6Q3.84 -7.5 3.12 -8.61Q2.4 -9.72 1.86 -10.5Q3.36 -12.54 4.8 -15.36Q6.24 -18.18 7.5 -21.48Q8.76 -24.78 9.78 -28.23Q10.8 -31.68 11.4 -34.86ZM15.36 -29.4Q15.9 -28.8 16.95 -27.27Q18 -25.74 19.23 -23.94Q20.46 -22.14 21.48 -20.61Q22.5 -19.08 22.86 -18.42L20.4 -15.06Q19.86 -16.2 18.93 -17.94Q18 -19.68 16.92 -21.54Q15.84 -23.4 14.88 -24.99Q13.92 -26.58 13.32 -27.48Z"/></g><g class="zh" id="zh2" style="transform:translate(470px,225.2px)"><path d="M6.24 -43.62H54V-39H6.24ZM3.12 -4.32H57.06V0.18H3.12ZM27.36 -41.28H32.34V-2.46H27.36Z"/></g><g class="zh" id="zh3" style="transform:translate(542px,225.2px)"><path d="M29.22 -40.38H57.72V-36.06H27.12ZM36.72 -27.36H56.34V-23.22H36.72ZM36.72 -14.1H57.12V-9.84H36.72ZM34.5 -38.94H39.06V4.74H34.5ZM31.56 -49.68 35.88 -48.54Q34.2 -43.8 31.95 -39.21Q29.7 -34.62 27.12 -30.6Q24.54 -26.58 21.78 -23.46Q21.42 -23.82 20.79 -24.42Q20.16 -25.02 19.47 -25.62Q18.78 -26.22 18.3 -26.52Q21 -29.34 23.46 -33.06Q25.92 -36.78 27.99 -41.04Q30.06 -45.3 31.56 -49.68ZM17.1 -50.16 21.42 -48.84Q19.5 -43.8 16.86 -38.79Q14.22 -33.78 11.16 -29.43Q8.1 -25.08 4.8 -21.66Q4.56 -22.2 4.08 -23.07Q3.6 -23.94 3.09 -24.84Q2.58 -25.74 2.16 -26.22Q5.16 -29.16 7.92 -33Q10.68 -36.84 13.05 -41.25Q15.42 -45.66 17.1 -50.16ZM10.74 -34.74 15.18 -39.24 15.24 -39.12V4.68H10.74Z"/></g><g class="zh" id="zh4" style="transform:translate(614px,225.2px)"><path d="M27.66 -19.26H32.28V1.08H27.66ZM10.38 -35.58H50.1V-31.68H10.38ZM3.54 -0.96H56.7V3.12H3.54ZM8.94 -12.96H51.36V-9H8.94ZM36.54 -28.74 39.84 -30.96Q41.94 -29.34 44.19 -27.39Q46.44 -25.44 48.45 -23.49Q50.46 -21.54 51.66 -19.98L48.18 -17.52Q47.04 -19.08 45.09 -21.03Q43.14 -22.98 40.89 -25.02Q38.64 -27.06 36.54 -28.74ZM4.2 -45.06H55.86V-34.44H51.3V-40.98H8.58V-34.44H4.2ZM11.4 -18.18Q11.28 -18.66 11.04 -19.41Q10.8 -20.16 10.56 -20.97Q10.32 -21.78 10.08 -22.32Q10.92 -22.44 11.97 -23.01Q13.02 -23.58 14.16 -24.48Q15.06 -25.08 16.98 -26.67Q18.9 -28.26 21.21 -30.45Q23.52 -32.64 25.44 -35.04L29.16 -32.64Q25.74 -29.04 21.9 -25.86Q18.06 -22.68 14.28 -20.34V-20.28Q14.28 -20.28 13.83 -20.07Q13.38 -19.86 12.81 -19.56Q12.24 -19.26 11.82 -18.9Q11.4 -18.54 11.4 -18.18ZM11.4 -18.18 11.34 -21.18 14.04 -22.68 45.48 -24.9Q45.6 -24.12 45.84 -23.13Q46.08 -22.14 46.2 -21.48Q37.2 -20.82 31.2 -20.31Q25.2 -19.8 21.54 -19.5Q17.88 -19.2 15.87 -18.99Q13.86 -18.78 12.93 -18.57Q12 -18.36 11.4 -18.18ZM26.1 -49.74 30.42 -51Q31.44 -49.44 32.4 -47.55Q33.36 -45.66 33.78 -44.22L29.28 -42.78Q28.86 -44.16 27.96 -46.17Q27.06 -48.18 26.1 -49.74Z"/></g><g id="sub"><g transform="translate(437.58 252.4)"><rect fill="#D7262C" width="33" height="22"/><rect fill="#0A1F8F" width="16.5" height="11"/><path fill="#F5F5F3" d="M8.25 2.2L7.82 3.91L8.68 3.91ZM9.9 2.64L8.68 3.91L9.42 4.33ZM11.11 3.85L9.42 4.33L9.84 5.07ZM11.55 5.5L9.84 5.07L9.84 5.93ZM11.11 7.15L9.84 5.93L9.42 6.67ZM9.9 8.36L9.42 6.67L8.68 7.09ZM8.25 8.8L8.68 7.09L7.82 7.09ZM6.6 8.36L7.82 7.09L7.08 6.67ZM5.39 7.15L7.08 6.67L6.66 5.93ZM4.95 5.5L6.66 5.93L6.66 5.07ZM5.39 3.85L6.66 5.07L7.08 4.33ZM6.6 2.64L7.08 4.33L7.82 3.91Z"/><circle fill="#0A1F8F" cx="8.25" cy="5.5" r="1.65"/><circle fill="#F5F5F3" cx="8.25" cy="5.5" r="1.39"/></g><path d="M0.2 -12.4H3.8V0H5.5V-12.4H9.1V-14H0.2Z" transform="translate(482.58 270.4)"/><path d="M2.22 -2.84Q2.22 -3.34 2.46 -3.7Q2.7 -4.06 3.19 -4.26Q3.68 -4.46 4.46 -4.46Q5.3 -4.46 6.04 -4.25Q6.78 -4.04 7.48 -3.56V-4.5Q7.34 -4.68 6.94 -4.97Q6.54 -5.26 5.87 -5.49Q5.2 -5.72 4.2 -5.72Q2.5 -5.72 1.55 -4.91Q0.6 -4.1 0.6 -2.76Q0.6 -1.82 1.04 -1.16Q1.48 -0.5 2.21 -0.15Q2.94 0.2 3.78 0.2Q4.54 0.2 5.31 -0.08Q6.08 -0.36 6.61 -0.94Q7.14 -1.52 7.14 -2.4L6.82 -3.6Q6.82 -2.88 6.47 -2.33Q6.12 -1.78 5.53 -1.48Q4.94 -1.18 4.2 -1.18Q3.62 -1.18 3.17 -1.37Q2.72 -1.56 2.47 -1.94Q2.22 -2.32 2.22 -2.84ZM1.98 -7.08Q2.2 -7.24 2.58 -7.46Q2.96 -7.68 3.51 -7.84Q4.06 -8 4.74 -8Q5.16 -8 5.54 -7.92Q5.92 -7.84 6.21 -7.66Q6.5 -7.48 6.66 -7.17Q6.82 -6.86 6.82 -6.38V0H8.42V-6.6Q8.42 -7.5 7.97 -8.12Q7.52 -8.74 6.71 -9.07Q5.9 -9.4 4.82 -9.4Q3.54 -9.4 2.63 -9.02Q1.72 -8.64 1.2 -8.26Z" transform="translate(496.28 270.4)"/><path d="M1.5 -13Q1.5 -12.56 1.83 -12.23Q2.16 -11.9 2.6 -11.9Q3.06 -11.9 3.38 -12.23Q3.7 -12.56 3.7 -13Q3.7 -13.46 3.38 -13.78Q3.06 -14.1 2.6 -14.1Q2.16 -14.1 1.83 -13.78Q1.5 -13.46 1.5 -13ZM1.8 -9.2V0H3.4V-9.2Z" transform="translate(510.3 270.4)"/><path d="M0.1 -9.2 4.1 0.7 6.72 -6 9.5 0.7 13.5 -9.2H11.7L9.38 -3.18L6.7 -9.9L4.2 -3.22L1.9 -9.2Z" transform="translate(519.9 270.4)"/><path d="M2.22 -2.84Q2.22 -3.34 2.46 -3.7Q2.7 -4.06 3.19 -4.26Q3.68 -4.46 4.46 -4.46Q5.3 -4.46 6.04 -4.25Q6.78 -4.04 7.48 -3.56V-4.5Q7.34 -4.68 6.94 -4.97Q6.54 -5.26 5.87 -5.49Q5.2 -5.72 4.2 -5.72Q2.5 -5.72 1.55 -4.91Q0.6 -4.1 0.6 -2.76Q0.6 -1.82 1.04 -1.16Q1.48 -0.5 2.21 -0.15Q2.94 0.2 3.78 0.2Q4.54 0.2 5.31 -0.08Q6.08 -0.36 6.61 -0.94Q7.14 -1.52 7.14 -2.4L6.82 -3.6Q6.82 -2.88 6.47 -2.33Q6.12 -1.78 5.53 -1.48Q4.94 -1.18 4.2 -1.18Q3.62 -1.18 3.17 -1.37Q2.72 -1.56 2.47 -1.94Q2.22 -2.32 2.22 -2.84ZM1.98 -7.08Q2.2 -7.24 2.58 -7.46Q2.96 -7.68 3.51 -7.84Q4.06 -8 4.74 -8Q5.16 -8 5.54 -7.92Q5.92 -7.84 6.21 -7.66Q6.5 -7.48 6.66 -7.17Q6.82 -6.86 6.82 -6.38V0H8.42V-6.6Q8.42 -7.5 7.97 -8.12Q7.52 -8.74 6.71 -9.07Q5.9 -9.4 4.82 -9.4Q3.54 -9.4 2.63 -9.02Q1.72 -8.64 1.2 -8.26Z" transform="translate(537.9 270.4)"/><path d="M7.4 -5.6V0H9V-5.8Q9 -7.46 8.15 -8.43Q7.3 -9.4 5.84 -9.4Q4.94 -9.4 4.25 -9Q3.56 -8.6 3.1 -7.76V-9.2H1.5V0H3.1V-5.6Q3.1 -6.28 3.39 -6.8Q3.68 -7.32 4.21 -7.61Q4.74 -7.9 5.44 -7.9Q6.4 -7.9 6.9 -7.32Q7.4 -6.74 7.4 -5.6Z" transform="translate(551.92 270.4)"/></g><rect id="seal" x="727.72" y="177.6" width="25.89" height="44.8" fill="none" stroke="currentColor" stroke-width="1.3" pathLength="1"/></svg>
<div id="credit">Design by Archie Kuo</div>
<script>
(function(){
var svg=document.getElementById('splash'); if(!svg) return;
var C={"zhX0": 326.0, "zhX": [0, 72.0, 144.0, 216.0, 288.0], "zhY": 225.2, "seal": [[733.0495999999999, 197.7152], [733.0495999999999, 216.29824000000002]], "sZ": 0.25386666666666663}, anims=[];
var en=[].slice.call(svg.querySelectorAll('.en')), zh=[].slice.call(svg.querySelectorAll('.zh'));
var sub=svg.querySelector('#sub'), seal=svg.querySelector('#seal');
var reduced=matchMedia('(prefers-reduced-motion: reduce)').matches;
var outE='cubic-bezier(.16,1,.3,1)', inoutE='cubic-bezier(.7,0,.2,1)';
function A(el,kf,o){var a=el.animate(kf,Object.assign({fill:'forwards'},o));anims.push(a);return a;}
function T(x,y,s){return 'translate('+x+'px,'+y+'px) scale('+(s||1)+')';}
function play(){
  anims.forEach(function(a){a.cancel()}); anims=[];
  if(reduced){finalState();return;}
  // 0: 杰構工作室 is simply there
  zh.forEach(function(g,i){g.style.transformOrigin='0 0';g.style.opacity=1;g.style.transform=T(C.zhX0+C.zhX[i],C.zhY,1);});
  // 0.9: 工作室 fades, 杰構 folds into seal
  zh.slice(2).forEach(function(g,i){A(g,[{opacity:1},{opacity:0}],{duration:200,delay:800+i*30,easing:inoutE});});
  zh.slice(0,2).forEach(function(g,i){
    A(g,[{transform:T(C.zhX0+C.zhX[i],C.zhY,1)},{transform:T(C.seal[i][0],C.seal[i][1],C.sZ)}],{duration:520,delay:880+i*40,easing:inoutE});});
  A(seal,[{strokeDashoffset:1},{strokeDashoffset:0}],{duration:450,delay:1200,easing:outE});
  // 1.15: KUØ WORKS letters fade in left to right
  en.forEach(function(g,i){A(g,[{opacity:0,transform:g.style.transform+' translateX(-6px)'},{opacity:1,transform:g.style.transform+' translateX(0)'}],{duration:320,delay:1050+i*45,easing:outE});});
  // 2.0: subtitle 杰構工作室 · from taiwan
  A(sub,[{opacity:0,transform:'translateY(4px)'},{opacity:1,transform:'translateY(0)'}],{duration:350,delay:1900,easing:outE});
}
function finalState(){
  en.forEach(function(g){g.style.opacity=1;});
  zh.forEach(function(g,i){if(i<2){g.style.opacity=1;g.style.transformOrigin='0 0';g.style.transform=T(C.seal[i][0],C.seal[i][1],C.sZ);}else{g.style.opacity=0;}});
  sub.style.opacity=1; seal.style.strokeDashoffset=0;
}
svg.addEventListener('click',play); window.kuoSplash={play:play,final:finalState};
play();
})();
</script>
</body></html>
"""#
}

/// Covers the app with the brand animation at launch, then fades away.
struct BrandSplashCover: ViewModifier {
    @State private var showing = true
    @State private var started = false

    func body(content: Content) -> some View {
        content.overlay {
            if showing {
                BrandSplash(onStart: { started = true })
                    .background(BrandSplash.paper)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .accessibilityLabel("KUØ WORKS 杰構工作室")
                    // A tap skips the animation.
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { showing = false } }
                    .task(id: started) {
                        try? await Task.sleep(for: started ? BrandSplash.duration : BrandSplash.giveUp)
                        guard !Task.isCancelled else { return }
                        withAnimation(.easeOut(duration: 0.35)) { showing = false }
                    }
            }
        }
    }
}
