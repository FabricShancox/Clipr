import Foundation

/// Which optional event kinds a session listens for, beyond clicks.
struct SessionEventOptions: Equatable {
    var mouseMoves: Bool
    var keys: Bool
}
