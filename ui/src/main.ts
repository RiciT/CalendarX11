import type {
  DatePickerOutput,
  DateParseDetail,
  MagicDatePicker,
} from "@w3cj/magic-date-picker";
import { renderMiniCalendar } from "./calendar.ts";
import { callSave, callExit } from "./bridge.js";
import "./style.css";

//type defs
interface EventRecord {
  date: string; //ISO 8601 date portion
  dateText: string; //human-readable date
  time: string; //local time
  description: string;
  savedAt: string; //iso timestamp
}

type Screen = "date" | "details" | "done";

interface AppState {
  screen: Screen;
  dateOutput: DatePickerOutput | null;
  time: string;
  description: string;
}

//glob state
const state: AppState = {
  screen: "date",
  dateOutput: null,
  time: "",
  description: "",
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
        ></magic-date-picker>
      </div>

	  <!-- live parsing -->
      <div id="parse-feedback" class="parse-feedback" aria-live="polite"></div>

	  <!-- reveal after the picker fires -->
      <div id="confirmation" class="hidden confirmation">
        <div id="calendar-slot"></div>
        <div class="confirmation__footer">
          <div id="date-summary" class="confirmation__summary"></div>
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
  const calendarSlot = document.getElementById("calendar-slot")!;
  const dateSummary = document.getElementById("date-summary")!;
  const nextBtn = document.getElementById("next-btn") as HTMLButtonElement;

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

    const startDate = new Date(e.detail.start.iso);
    const endDate = e.detail.isRange ? new Date(e.detail.end.iso) : undefined;

    calendarSlot.innerHTML = renderMiniCalendar(startDate, true, endDate);
    dateSummary.innerHTML = `<span class="check-icon">✓</span> ${e.detail.text}`;

    confirmation.classList.remove("hidden");
    nextBtn.focus();
  }) as EventListener);

  //when cleared
  picker.addEventListener("date-clear", (() => {
    state.dateOutput = null;
    parseFeedback.textContent = "";
    confirmation.classList.add("hidden");
  }) as EventListener);

  //next button
  nextBtn.addEventListener("click", () => {
    if (state.dateOutput) {
      state.screen = "details";
      render();
    }
  });

  //also make it work on enter
  document.addEventListener(
    "keydown",
    (e: KeyboardEvent) => {
      if (
        e.key === "Enter" &&
        state.dateOutput &&
        !confirmation.classList.contains("hidden")
      ) {
        //only if focus is not inside the datepicker
        if (!picker.contains(document.activeElement)) {
          state.screen = "details";
          render();
        }
      }
    },
    { once: true },
  );

  //auto focus the picker onces opened
  requestAnimationFrame(() => picker.focus?.());
}

//screen 2 - time and description
function renderDetailsScreen(): void {
  //pre-fill time to now - i think this might be useful but could also be annoying so will need to test it out and see
  if (!state.time) {
    const now = new Date();
    const mins = now.getMinutes() < 30 ? 30 : 0;
    const hours =
      now.getMinutes() < 30 ? now.getHours() : (now.getHours() + 1) % 24;
    state.time = `${String(hours).padStart(2, "0")}:${String(mins).padStart(2, "0")}`;
  }

  const dateLabel = state.dateOutput?.text ?? "";

  app.innerHTML = `
    <div class="screen" id="details-screen">
      <header class="screen__header">
        <div class="screen__step">Step 2 of 2</div>
        <h1 class="screen__title">Add details</h1>
        <p class="screen__hint date-echo">
          <span class="check-icon">✓</span> ${dateLabel}
        </p>
      </header>

      <div class="form">
        <label class="form__label" for="time-input">
          Time
        </label>
        <input
          class="form__input form__input--time"
          id="time-input"
          type="time"
          value="${state.time}"
          aria-label="Event time"
        />

        <label class="form__label" for="desc-input">
          Description
          <span class="form__optional">(optional)</span>
        </label>
        <textarea
          class="form__input form__textarea"
          id="desc-input"
          rows="4"
          placeholder="What's this event about?"
          aria-label="Event description"
        >${state.description}</textarea>

        <div class="form__actions">
          <button id="back-btn" class="btn btn--ghost">← Back</button>
          <button id="save-btn" class="btn btn--primary">Save Event</button>
        </div>
      </div>
    </div>
  `;

  const timeInput = document.getElementById("time-input") as HTMLInputElement;
  const descInput = document.getElementById(
    "desc-input",
  ) as HTMLTextAreaElement;
  const backBtn = document.getElementById("back-btn") as HTMLButtonElement;
  const saveBtn = document.getElementById("save-btn") as HTMLButtonElement;

  //persist values to state on change
  timeInput.addEventListener("input", () => {
    state.time = timeInput.value;
  });
  descInput.addEventListener("input", () => {
    state.description = descInput.value;
  });

  backBtn.addEventListener("click", () => {
    state.screen = "date";
    render();
  });

  saveBtn.addEventListener("click", async () => {
    state.time = timeInput.value;
    state.description = descInput.value;
    saveBtn.disabled = true;
    saveBtn.textContent = "Saving…";
    await saveEvent();
  });

  //<C-<CR>> to save
  document.addEventListener("keydown", (e: KeyboardEvent) => {
    if (e.key === "Enter" && (e.ctrlKey || e.metaKey)) {
      saveBtn.click();
    }
  });

  timeInput.focus();
}

//screen 3 - done
function renderDoneScreen(): void {
  app.innerHTML = `
    <div class="screen screen--done" id="done-screen">
      <div class="done-icon">✓</div>
      <h1 class="screen__title">Event saved!</h1>
      <p class="screen__hint">
        ${state.dateOutput?.text ?? ""} at ${state.time}<br>
        <em id="exit-status">Closing window…</em>
      </p>
    </div>
  `;

  //request the closing from the endpoint in zig
  requestExit();
}

//POST - to zig
async function saveEvent(): Promise<void> {
  if (!state.dateOutput) return;

  const record = {
    date: state.dateOutput.start.iso.slice(0, 10),
    dateText: state.dateOutput.text,
    time: state.time,
    description: state.description.trim(),
    savedAt: new Date().toISOString(),
  };

  callSave(JSON.stringify(record, null, 2));
  state.screen = "done";
  render();
}

//auto-exit - POST to zig to close to window
function requestExit(): void {
  const statusEl = document.getElementById("exit-status");
  const exited = callExit();
  if (!exited && statusEl) {
    statusEl.textContent = "You can close this window.";
  }
}

//start the event flow
render();
