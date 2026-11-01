import CoreGraphics
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
for w in list where (w["kCGWindowOwnerName"] as? String) == "Termaid" && (w["kCGWindowName"] as? String) == "Library" { print(w["kCGWindowNumber"]!) }
