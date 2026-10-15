/// Board geometry and coordinate helpers shared by the whole engine.
///
/// Token positions are *relative to the owning seat*:
///
/// * `-1`      yard (not yet entered)
/// * `0..50`   main track (51 squares walked by every token)
/// * `51..55`  home column (only reachable by the owner)
/// * `56`      finished
///
/// The shared 52-square perimeter is addressed by *absolute* squares `0..51`.
library;

/// Number of seats at the table (colours).
const int seatCount = 4;

/// Tokens owned by each seat.
const int tokensPerSeat = 4;

/// Squares on the shared outer perimeter.
const int trackSquares = 52;

/// Distance between the start squares of two neighbouring seats.
const int seatTrackOffset = 13;

/// Relative position of a token that is still in the yard.
const int yardPosition = -1;

/// Relative position of a seat's start (exit) square.
const int startPosition = 0;

/// Last relative position that lies on the shared track.
const int lastTrackPosition = 50;

/// First relative position inside the protected home column.
const int firstHomeColumnPosition = 51;

/// Last relative position inside the protected home column.
const int lastHomeColumnPosition = 55;

/// Relative position of a token that has reached home.
const int finishPosition = 56;

/// The 8 safe squares as absolute coordinates: the 4 start squares plus the
/// 4 star squares (8 steps after each start square).
const Set<int> safeSquares = {0, 13, 26, 39, 8, 21, 34, 47};

/// Whether [position] (relative) lies on the shared track.
bool isOnTrack(int position) =>
    position >= startPosition && position <= lastTrackPosition;

/// Whether [position] (relative) lies inside the protected home column.
bool isInHomeColumn(int position) =>
    position >= firstHomeColumnPosition && position <= lastHomeColumnPosition;

/// Converts a relative track position of [seat] into an absolute square.
///
/// Only valid for positions on the shared track (`0..50`).
int absoluteSquare(int seat, int relativePosition) {
  assert(
      isOnTrack(relativePosition), 'Position $relativePosition not on track');
  return (relativePosition + seat * seatTrackOffset) % trackSquares;
}

/// Whether the absolute [square] is one of the 8 safe squares.
bool isSafeSquare(int square) => safeSquares.contains(square);

/// The seat sitting opposite [seat] (its teammate in 2v2 play).
int partnerOf(int seat) => (seat + 2) % seatCount;
