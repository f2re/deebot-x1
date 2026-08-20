const $ = (selector) => document.querySelector(selector);
const selected = new Set();
let csrf = "";

function toast(text) {
  const element = $("#toast");
  element.textContent = text;
  element.classList.add("show");
  setTimeout(() => element.classList.remove("show"), 2200);
}

async function requestJson(url, options = {}) {
  const opts = { ...options };
  if ((opts.method || "GET").toUpperCase() !== "GET") {
    opts.headers = { ...(opts.headers || {}), "X-DEEBOT-CSRF": csrf };
  }
  const response = await fetch(url, opts);
  if (!response.ok) throw new Error(await response.text());
  return response.json();
}

function humanState(state) {
  return (
    {
      docked: "На базе",
      idle: "Готов",
      cleaning: "Уборка",
      paused: "Пауза",
      returning: "Возвращается",
      error: "Ошибка",
      unavailable: "Нет связи",
    }[state] ||
    state ||
    "—"
  );
}

async function loadSession() {
  const data = await requestJson("/api/session");
  csrf = data.csrf || "";
  if (!csrf) throw new Error("Не удалось создать локальную сессию");
}

async function status() {
  try {
    const data = await requestJson("/api/status");
    $("#name").textContent = data.name || "DEEBOT X1";
    $("#state").textContent = humanState(data.state);
    $("#battery").textContent = data.battery ?? "—";
    if (data.map_entity) {
      $("#map").src = `/api/map?t=${Date.now()}`;
      $("#map").onload = () => {
        $("#mapEmpty").style.display = "none";
      };
    }
  } catch (error) {
    $("#state").textContent = "Нет связи";
  }
}

async function loadAreas() {
  try {
    const data = await requestJson("/api/areas");
    const box = $("#areas");
    box.innerHTML = "";
    for (const area of data.areas) {
      const button = document.createElement("button");
      button.className = "area";
      button.textContent = area.name;
      button.dataset.id = area.id;
      button.onclick = () => {
        if (selected.has(area.id)) {
          selected.delete(area.id);
          button.classList.remove("selected");
        } else {
          selected.add(area.id);
          button.classList.add("selected");
        }
        $("#cleanAreas").disabled = !selected.size;
      };
      box.appendChild(button);
    }
    if (!data.areas.length) {
      box.innerHTML =
        '<span class="muted">Нет сопоставленных комнат. В Home Assistant откройте DEEBOT X1 → настройки → «Map vacuum segments to areas».</span>';
    }
  } catch (error) {
    $("#areas").innerHTML =
      '<span class="muted">Не удалось получить комнаты</span>';
  }
}

async function action(name) {
  try {
    await requestJson(`/api/action/${name}`, { method: "POST" });
    toast("Команда отправлена");
    setTimeout(status, 1200);
  } catch (error) {
    toast("Ошибка команды");
  }
}

document.querySelectorAll("[data-action]").forEach((button) => {
  button.onclick = () => action(button.dataset.action);
});

$("#cleanAreas").onclick = async () => {
  try {
    await requestJson("/api/clean-areas", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ areas: [...selected] }),
    });
    toast("Уборка выбранных комнат запущена");
    setTimeout(status, 1200);
  } catch (error) {
    toast("Уборка комнат не запустилась");
  }
};

$("#refresh").onclick = status;

(async () => {
  try {
    await loadSession();
    await Promise.all([status(), loadAreas()]);
    setInterval(status, 10000);
  } catch (error) {
    $("#state").textContent = "Ошибка локальной сессии";
  }
})();

if ("serviceWorker" in navigator) {
  navigator.serviceWorker.register("/sw.js").catch(() => {});
}
