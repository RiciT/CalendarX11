//for the mini-calendar
const MONTH_NAMES = [
  "January",
  "February",
  "March",
  "April",
  "May",
  "June",
  "July",
  "August",
  "September",
  "October",
  "November",
  "December",
];
const DAY_NAMES = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"];

export function renderMiniCalendar(
  date: Date,
  confirmed = false,
  endDate?: Date,
): string {
  const year = date.getFullYear();
  const month = date.getMonth();
  const selectedDay = date.getDate();

  const rangeStart = confirmed ? date : null;
  const rangeEnd = confirmed && endDate ? endDate : null;

  const firstWeekday = new Date(year, month, 1).getDay(); // 0 = Sun
  const daysInMonth = new Date(year, month + 1, 0).getDate();
  const today = new Date();
  const todayStr = `${today.getFullYear()}-${today.getMonth()}-${today.getDate()}`;

  let html = `<div class="mini-cal${confirmed ? " mini-cal--confirmed" : ""}">`;
  html += `<div class="mini-cal__header">`;
  html += `<span class="mini-cal__month">${MONTH_NAMES[month]} ${year}</span>`;
  html += `</div>`;
  html += `<div class="mini-cal__grid">`;

  //day name header
  for (const d of DAY_NAMES) {
    html += `<div class="mini-cal__dayname">${d}</div>`;
  }

  //leading empty cells
  for (let i = 0; i < firstWeekday; i++) {
    html += `<div class="mini-cal__cell mini-cal__cell--empty"></div>`;
  }

  //day cells
  for (let d = 1; d <= daysInMonth; d++) {
    const cellDate = new Date(year, month, d);
    const cellStr = `${year}-${month}-${d}`;
    const isSelected = d === selectedDay;
    const isToday = cellStr === todayStr;
    const isInRange =
      rangeStart && rangeEnd && cellDate >= rangeStart && cellDate <= rangeEnd;

    const classes = [
      "mini-cal__cell",
      isSelected ? "mini-cal__cell--selected" : "",
      isToday && !isSelected ? "mini-cal__cell--today" : "",
      isInRange && !isSelected ? "mini-cal__cell--in-range" : "",
    ]
      .filter(Boolean)
      .join(" ");

    html += `<div class="${classes}">${d}</div>`;
  }

  html += `</div></div>`;
  return html;
}
