import { invoke } from "@tauri-apps/api/core";
import { getCurrentWindow } from "@tauri-apps/api/window";

const macInput = document.getElementById("mac") as HTMLInputElement;
const saveBtn = document.getElementById("save") as HTMLButtonElement;
const cancelBtn = document.getElementById("cancel") as HTMLButtonElement;
const errorDiv = document.getElementById("error") as HTMLDivElement;

const MAC_REGEX = /^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$/;

function validate(value: string): boolean {
  return MAC_REGEX.test(value.trim());
}

function updateValidationState() {
  const value = macInput.value;
  const hasInput = value.length > 0;
  const valid = validate(value);

  macInput.classList.toggle("invalid", hasInput && !valid);
  errorDiv.textContent =
    hasInput && !valid ? "Invalid format — expected xx:xx:xx:xx:xx:xx" : "";
  saveBtn.disabled = !valid;
}

invoke<{ keylight_mac: string }>("get_settings").then((s) => {
  macInput.value = s.keylight_mac;
  updateValidationState();
});

macInput.addEventListener("input", updateValidationState);

saveBtn.addEventListener("click", async () => {
  const mac = macInput.value.trim().toLowerCase();
  if (!validate(mac)) return;
  await invoke("save_settings", { mac });
  await getCurrentWindow().close();
});

cancelBtn.addEventListener("click", async () => {
  await getCurrentWindow().close();
});

// Allow Enter key to save
macInput.addEventListener("keydown", (e) => {
  if (e.key === "Enter" && !saveBtn.disabled) saveBtn.click();
  if (e.key === "Escape") cancelBtn.click();
});
