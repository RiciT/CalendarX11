import "@w3cj/magic-date-picker/bundled";
import type {
  DatePickerOutput,
  DateParseDetail,
  MagicDatePicker,
} from "@w3cj/magic-date-picker";
import { callSave, callExit, callReady } from "./bridge.js";
import "./style.css";

//type defs
interface EventRecord {
  date: string;
  dateEnd?: string;
  dateText: string;
  wholeDay: boolean;
  timeStart?: string;
  timeEnd?: string;
  title: string;
  description: string;
  savedAt: string;
}

type Screen = "date" | "details" | "done";

interface AppState {
  screen: Screen;
  dateOutput: DatePickerOutput | null;
  timeStart: string;
  timeEnd: string;
  title: string;
  description: string;
  wholeDay: boolean;
}

function nextHalfHour(offsetHalfHours = 0): string {
  const now = new Date();
  const totalMins = now.getHours() * 60 + now.getMinutes();
  const rounded = Math.ceil(totalMins / 30) * 30 + offsetHalfHours * 30;
  const h = Math.floor(rounded / 60) % 24;
  const m = rounded % 60;
  return `${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}`;
}

//glob state
const state: AppState = {
  screen: "date",
  dateOutput: null,
  timeStart: "",
  timeEnd: "",
  title: "",
  description: "",
  wholeDay: false,
};

const app = document.getElementById("app")!;

//main router function
function render(): void {
  switch (state.screen) {
    case "date":
      renderDateScreen();
      break;
    case "details":
      renderDetailsScreen();
      break;
    case "done":
      renderDoneScreen();
      break;
  }
}

//screen 1 - date selection
function renderDateScreen(): void {
  const ac = new AbortController();
  const { signal } = ac;

  app.innerHTML = `
    <div class="screen" id="date-screen">
      <header class="screen__header">
        <div class="screen__step">Step 1 of 2</div>
        <h1 class="screen__title">When is the event?</h1>
      </header>
      <div class="picker-wrapper">
        <magic-date-picker
          id="date-picker"
          placeholder="Type here..."
          theme="dark"
		  locale="en-EN"
        ></magic-date-picker>
      </div>
      <!-- live parsing -->
      <div id="parse-feedback" class="parse-feedback" aria-live="polite"></div>
      <!-- reveal after the picker fires -->
      <div id="confirmation" class="hidden confirmation">
        <div id="calendar-slot"></div>
        <div class="confirmation__footer">
          <button id="next-btn" class="btn btn--primary">
            Next <span class="btn__arrow">→</span>
          </button>
        </div>
      </div>
    </div>
  `;

  const picker = document.getElementById("date-picker") as MagicDatePicker;
  const parseFeedback = document.getElementById("parse-feedback")!;
  const confirmation = document.getElementById("confirmation")!;
  const nextBtn = document.getElementById("next-btn") as HTMLButtonElement;

  function advance() {
    if (!state.dateOutput) return;
    ac.abort();
    state.screen = "details";
    render();
  }

  //live feedback
  picker.addEventListener("date-parse", ((e: CustomEvent<DateParseDetail>) => {
    const { text, alternativesDescription } = e.detail;
    if (!text.trim()) {
      parseFeedback.textContent = "";
      return;
    }
    if (alternativesDescription) {
      parseFeedback.innerHTML = `<span class="parse-feedback__ambiguous">⚠ ${alternativesDescription}</span>`;
    } else {
      parseFeedback.innerHTML = `<span class="parse-feedback__ok">✓ Parsed: <strong>${text}</strong></span>`;
    }
  }) as EventListener);

  //date is actually confirmed
  picker.addEventListener("date-change", ((
    e: CustomEvent<DatePickerOutput>,
  ) => {
    state.dateOutput = e.detail;
    parseFeedback.textContent = "";
    confirmation.classList.remove("hidden");
    confirmation.classList.remove("hidden");
    setTimeout(() => nextBtn.focus(), 0);
  }) as EventListener);

  //when cleared
  picker.addEventListener("date-clear", (() => {
    state.dateOutput = null;
    parseFeedback.textContent = "";
    confirmation.classList.add("hidden");
  }) as EventListener);

  //next button
  nextBtn.addEventListener("click", advance);

  //also make it work on enter - only if focus is not inside the datepicker
  document.addEventListener(
    "keydown",
    (e: KeyboardEvent) => {
      if (e.key !== "Enter") return;
      if (document.activeElement !== nextBtn) return;
      e.preventDefault();
      advance();
    },
    { signal },
  );

  //auto focus the picker once opened
  customElements.whenDefined("magic-date-picker").then(() => {
    requestAnimationFrame(() => {
      picker.focus?.();
      callReady();
    });
  });
}

//screen 2 - time and description
function renderDetailsScreen(): void {
  const ac = new AbortController();
  const { signal } = ac;

  const isRange = state.dateOutput?.isRange ?? false;
  const dateLabel = state.dateOutput?.text ?? "";

  //pre-fill time to now - i think this might be useful but could also be annoying so will need to test it out and see
  if (!state.timeStart) state.timeStart = nextHalfHour(0);
  if (!state.timeEnd) state.timeEnd = nextHalfHour(2);

  app.innerHTML = `
    <div class="screen" id="details-screen">
      <header class="screen__header">
        <div class="screen__step">Step 2 of 2</div>
        <h1 class="screen__title">Add details</h1>
        <p class="screen__hint date-echo">
          <span class="check-icon">✓</span> ${dateLabel}
          ${isRange ? '<span class="badge">whole day range</span>' : ""}
        </p>
      </header>
      <div class="form">
        ${
          !isRange
            ? `
        <div class="form__label">Time</div>

		<div class="time-row">
			<div class="time-range ${state.wholeDay ? "time-range--hidden" : ""}" id="time-range">
				<div class="time-range__slot" id="slot-start" tabindex="${state.wholeDay ? -1 : 0}" role="spinbutton" aria-label="Start time" aria-valuenow="${state.timeStart}">
					${renderTimeDisplay(state.timeStart)}
				</div>
				<div class="time-range__sep">→</div>
				<div class="time-range__slot" id="slot-end" tabindex="${state.wholeDay ? -1 : 0}" role="spinbutton" aria-label="End time" aria-valuenow="${state.timeEnd}">
					${renderTimeDisplay(state.timeEnd)}
				</div>
			</div>
			<button
				id="wholeday-btn"
				class="btn btn--toggle" ${state.wholeDay ? "btn--toggle-on" : ""}"
				tabindex = 0
				aria-pressed="${state.wholeDay}"
				title="Whole day event"
			>All day</button>
		</div>
        <p class="form__hint">Tab between fields · ↑↓ adjust · ←→ hour/minute</p>
        `
            : ""
        }
		<label class="form__label" for="title-input">
			Title
		</label>
		<input
		  class="form__input"
		  id="title-input"
		  type="text"
		  placeholder=""
		  aria-label="Event title"
		  value="${state.title}"
		/>
        <label class="form__label" for="desc-input">
          Description
        </label>
        <textarea
          class="form__input form__textarea"
          id="desc-input"
          rows="4"
          placeholder=""
          aria-label="Event description"
        >${state.description}</textarea>
        <div class="form__actions">
          <button id="back-btn" class="btn btn--ghost" tabindex="0">← Back</button>
          <button id="save-btn" class="btn btn--primary" tabindex="0">Save Event</button>
        </div>
      </div>
    </div>
  `;

  const descInput = document.getElementById(
    "desc-input",
  ) as HTMLTextAreaElement;
  const titleInput = document.getElementById("title-input") as HTMLInputElement;
  const backBtn = document.getElementById("back-btn") as HTMLButtonElement;
  const saveBtn = document.getElementById("save-btn") as HTMLButtonElement;
  const wholeDayBtn = document.getElementById(
    "wholeday-btn",
  ) as HTMLButtonElement;

  //persist values to state on change
  descInput.addEventListener("input", () => {
    state.description = descInput.value;
  });

  titleInput.addEventListener("input", () => {
    state.title = titleInput.value;
  });

  backBtn.addEventListener("click", () => {
    ac.abort();
    state.wholeDay = false;
    state.title = "";
    state.description = "";
    state.screen = "date";
    render();
  });

  async function doSave() {
    state.description = descInput.value;
    state.title = titleInput.value;
    saveBtn.disabled = true;
    saveBtn.textContent = "Saving...";
    ac.abort();
    await saveEvent();
  }

  saveBtn.addEventListener("click", doSave);

  //enter to save - but let textarea handle its own enter (newline),
  //back button handle its own enter, and time slots handle arrows only
  document.addEventListener(
    "keydown",
    (e: KeyboardEvent) => {
      if (e.key !== "Enter") return;
      const focused = document.activeElement;
      if (focused === titleInput) return;
      if (focused === descInput) return;
      if (focused === backBtn) {
        backBtn.click();
        return;
      }
      if (focused === wholeDayBtn) {
        wholeDayBtn.click();
        return;
      }
      if (focused?.classList.contains("time-range__slot")) return;
      e.preventDefault();
      doSave();
    },
    { signal },
  );

  if (!isRange) {
    wholeDayBtn.addEventListener("click", () => {
      state.wholeDay = !state.wholeDay;
      //rerender details
      ac.abort();
      render();
      requestAnimationFrame(() => {
        document.getElementById("wholeday-btn")?.focus();
      });
    });
  }

  if (!isRange && !state.wholeDay) {
    const slotStart = document.getElementById("slot-start")!;
    const slotEnd = document.getElementById("slot-end")!;
    initTimeSlot(slotStart, "start", signal);
    initTimeSlot(slotEnd, "end", signal);
    slotStart.focus();
  } else {
    titleInput.focus();
  }
}

//time slot spinner - renders HH:MM with individually selectable hour/minute parts
function renderTimeDisplay(time: string): string {
  const [h, m] = time.split(":");
  return `
    <span class="time-range__part time-range__hour">${h}</span>
    <span class="time-range__colon">:</span>
    <span class="time-range__part time-range__minute">${m}</span>
  `;
}

type TimePart = "hour" | "minute";
type TimeSlotId = "start" | "end";

function initTimeSlot(
  el: HTMLElement,
  id: TimeSlotId,
  signal: AbortSignal,
): void {
  let activePart: TimePart = "hour";

  function getTime(): [number, number] {
    const val = id === "start" ? state.timeStart : state.timeEnd;
    const [h, m] = val.split(":").map(Number);
    return [h, m];
  }

  function setTime(h: number, m: number): void {
    const str = `${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}`;
    if (id === "start") state.timeStart = str;
    else state.timeEnd = str;
    el.setAttribute("aria-valuenow", str);
    el.innerHTML = renderTimeDisplay(str);
    highlightPart();
  }

  function highlightPart(): void {
    el.querySelectorAll(".time-range__part").forEach((p) =>
      p.classList.remove("active"),
    );
    const cls =
      activePart === "hour" ? ".time-range__hour" : ".time-range__minute";
    el.querySelector(cls)?.classList.add("active");
  }

  el.addEventListener(
    "focus",
    () => {
      el.classList.add("time-range__slot--focused");
      highlightPart();
    },
    { signal },
  );

  el.addEventListener(
    "blur",
    () => {
      el.classList.remove("time-range__slot--focused");
      el.querySelectorAll(".time-range__part").forEach((p) =>
        p.classList.remove("active"),
      );
    },
    { signal },
  );

  el.addEventListener(
    "keydown",
    (e: KeyboardEvent) => {
      const [h, m] = getTime();
      switch (e.key) {
        case "m":
          e.preventDefault();
          activePart = "hour";
          highlightPart();
          break;
        case "i":
          e.preventDefault();
          activePart = "minute";
          highlightPart();
          break;
        case "e":
          e.preventDefault();
          activePart === "hour"
            ? setTime((h + 1) % 24, m)
            : setTime(h, (m + 5) % 60);
          break;
        case "n":
          e.preventDefault();
          activePart === "hour"
            ? setTime((h + 23) % 24, m)
            : setTime(h, (m + 55) % 60);
          break;
        case "E":
          e.preventDefault();
          activePart === "hour"
            ? setTime((h + 1) % 24, m)
            : setTime(h, (m + 1) % 60);
          break;
        case "N":
          e.preventDefault();
          activePart === "hour"
            ? setTime((h + 23) % 24, m)
            : setTime(h, (m + 59) % 60);
          break;
        case "PageUp":
          e.preventDefault();
          activePart === "hour"
            ? setTime((h + 1) % 24, m)
            : setTime(h, (m + 15) % 60);
          break;
        case "PageDown":
          e.preventDefault();
          activePart === "hour"
            ? setTime((h + 23) % 24, m)
            : setTime(h, (m + 45) % 60);
          break;
      }
    },
    { signal },
  );

  //click on hour or minute part to activate it
  el.addEventListener(
    "click",
    (e: MouseEvent) => {
      const target = e.target as HTMLElement;
      if (target.classList.contains("time-range__hour")) activePart = "hour";
      if (target.classList.contains("time-range__minute"))
        activePart = "minute";
      highlightPart();
    },
    { signal },
  );
}

//screen 3 - done
function renderDoneScreen(): void {
  const isRange = state.dateOutput?.isRange ?? false;
  const timeInfo = isRange
    ? "whole day range"
    : `${state.timeStart} → ${state.timeEnd}`;

  app.innerHTML = `
    <div class="screen screen--done" id="done-screen">
      <div class="done-icon">✓</div>
      <h1 class="screen__title">Event saved!</h1>
      <p class="screen__hint">
        ${state.dateOutput?.text ?? ""}<br>
        ${timeInfo}<br>
        <em id="exit-status">Closing window...</em>
      </p>
    </div>
  `;
  //request the closing from the endpoint in zig
  requestExit();
}

//POST - to zig
async function saveEvent(): Promise<void> {
  if (!state.dateOutput) return;
  const isRange = state.dateOutput.isRange;
  const wholeDay = isRange || state.wholeDay;
  const record: EventRecord = {
    date: state.dateOutput.start.iso.slice(0, 10),
    dateEnd: isRange ? state.dateOutput.end.iso.slice(0, 10) : undefined,
    dateText: state.dateOutput.text,
    wholeDay,
    timeStart: wholeDay ? undefined : state.timeStart,
    timeEnd: wholeDay ? undefined : state.timeEnd,
    title: state.title.trim(),
    description: state.description.trim(),
    savedAt: new Date().toISOString(),
  };
  callSave(JSON.stringify(record, null, 2));
  state.screen = "done";
  render();
}

//auto-exit - POST to zig to close the window
function requestExit(): void {
  const statusEl = document.getElementById("exit-status");
  const exited = callExit();
  if (!exited && statusEl) {
    statusEl.textContent = "You can close this window.";
  }
}

//start the event flow
render();
