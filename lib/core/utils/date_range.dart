/// The half-open `[from, to)` span covering every moment of the calendar days
/// [start] to [end], both included. Use `from <= t < to`: the picker returns
/// midnight at the start of the last day, so `t <= end` would lose that day.
({DateTime from, DateTime to}) wholeDays(DateTime start, DateTime end) => (
      from: DateTime(start.year, start.month, start.day),
      to: DateTime(end.year, end.month, end.day + 1),
    );

/// True when [moment] falls in the `[from, to)` span of [wholeDays].
bool withinSpan(DateTime moment, DateTime from, DateTime to) =>
    !moment.isBefore(from) && moment.isBefore(to);
