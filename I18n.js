.pragma library
// Interface text in other languages, keyed by the English text itself, so a
// string missing from a table shows in English. tr("… %1", x) fills in %1, %2…
// after the lookup.
var TABLES = {
  ru: {
    "Workspaces": "Рабочие столы",
    "Save": "Сохранить",
    "Set up sessions": "Настроить сессии",
    "Open windows": "Открытые окна",
    "Now on the desks": "Сейчас на столах",
    "Take the open windows": "Взять открытые окна",
    "Save to": "Сохранить в",
    "Not saved: %1": "Не сохранятся: %1",
    "Save the open windows as a new session": "Сохранить открытые окна в новую сессию",
    "Save the open windows to %1": "Сохранить открытые окна в «%1»",
    "Save the open windows to %1?": "Сохранить открытые окна в «%1»?",
    "config.json is broken — session %1 not started": "config.json сломан — сессия «%1» не запущена",
    "config.json is broken — the scheduled session was not checked": "config.json сломан — сессия по расписанию не проверялась",
    "config.json is broken, edits are off: %1": "config.json сломан, правка отключена: %1",
    "Not closed: %1": "Не закрыто: %1",
    "No session": "Без сессии",
    "All": "Все",
    "Apps by place": "Приложения по местам",
    "by window": "по окну",
    "Desk %1": "Стол %1",
    "free": "свободный",
    "none": "нет",
    "place %1": "место %1",
    "Schedule": "Расписание",
    "Schedule: %1": "Расписание: %1",
    "Ask": "Спросить",
    "Back": "Назад",
    "By window": "По окну",
    "Cancel": "Отмена",
    "Close and switch": "Закрыть и сменить",
    "Closing: %1": "Закрываем: %1",
    "Days": "Дни",
    "End the session first": "Сначала завершите сессию",
    "From": "С",
    "HH:MM": "ЧЧ:ММ",
    "To": "До",
    "Collapsing in a session": "Схлопывание в сессии",
    "Collapsing without a session": "Схлопывание без сессии",
    "Custom": "Своё",
    "Delete": "Удалить",
    "Clear": "Очистить",
    "Scratchpad": "Скретчпад",
    "Clear the scratchpad?": "Очистить скретчпад?",
    "Clear desk %1?": "Очистить стол %1?",
    "Clear the desk": "Очистить стол",
    "Delete rule": "Удалить правило",
    "Delete session": "Удалить сессию",
    "Delete session %1?": "Удалить сессию «%1»?",
    "Don't collapse": "Не схлопывать",
    "Empty": "Пусто",
    "Floating": "Плавающее",
    "Focus": "Фокус",
    "Foreign window on a laid-out desk": "Чужое окно на столе со схемой",
    "Fri": "Пт",
    "Grid": "Сетка",
    "Launch one by one": "Запускать по очереди", "Hide the name without a session": "Скрывать название без сессии",
    "Launching…": "Запускаем…",
    "Left and right": "Слева и справа",
    "Main on the left": "Главное слева",
    "Main on the right": "Главное справа",
    "Mon": "Пн",
    "Name": "Название",
    "New session": "Новая сессия",
    "Next desk": "На следующий стол",
    "No matches": "Ничего не найдено",
    "Number": "Номер",
    "One app window": "Одно окно приложения",
    "One window": "Одно окно",
    "Only free": "Только свободные",
    "Overlaps with %1": "Пересекается с «%1»",
    "Pick the days": "Выберите дни",
    "Regular": "Обычные",
    "Launch the apps": "Запустить приложения",
    "Switch to this set": "Переключиться на этот набор",
    "Rename session": "Переименовать сессию",
    "Type a name": "Введите имя",
    "This name is taken by the regular desks": "Это имя занято обычными столами",
    "A session with this name exists": "Сессия с таким именем уже есть",
    "Replace": "Заменить",
    "Sat": "Сб",
    "Scheduled session at login": "Сессия по расписанию при входе",
    "Scheme": "Схема",
    "Search…": "Поиск…",
    "Session name": "Имя сессии",
    "Settings": "Настройки",
    "Stays": "Остаётся",
    "Sun": "Вс",
    "Switch to %1?": "Сменить на «%1»?",
    "The end must be after the start": "Конец должен быть позже начала",
    "Thu": "Чт",
    "Time is HH:MM": "Время — ЧЧ:ММ",
    "Top and bottom": "Сверху и снизу",
    "Tue": "Вт",
    "Turn off the session?": "Выключить сессию?",
    "Waiting for the flash drive…": "Ждём флешку…",
    "Wed": "Ср",
    "Window class, Enter to add": "Класс окна, Enter — добавить"
  }
}

// Text follows LC_MESSAGES, overridden by LC_ALL and defaulting to LANG, as
// the system splits it. env is name -> value (Quickshell.env in QML).
function textLanguage(env) {
  var names = ["LC_ALL", "LC_MESSAGES", "LANG"]
  for (var i = 0; i < names.length; i++) {
    var v = String(env(names[i]) || "").split(".")[0].split("@")[0]
    if (v && v !== "C" && v !== "POSIX") {
      var l = v.slice(0, 2).toLowerCase()
      return TABLES[l] ? l : "en"
    }
  }
  return "en"
}

function translator(lang) {
  var table = TABLES[lang] || {}
  return function(text) {
    var out = Object.prototype.hasOwnProperty.call(table, text) ? table[text] : text
    for (var i = 1; i < arguments.length; i++) out = out.split("%" + i).join(String(arguments[i]))
    return out
  }
}
