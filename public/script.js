// Клиентская логика «Умного калькулятора».
// Вычисления выполняет сервер (POST /calculate); здесь - ввод, проверки и показ результата.
(function () {
  'use strict';

  const MAX_NUMBER_LENGTH = 16; // максимальная длина вводимого числа
  const LONG_RESULT_LENGTH = 20; // после этого результат сворачивается
  const MAX_HISTORY = 10;

  const state = {
    expression: '',
    justCalculated: false,
    lastPlain: '',
    lastResult: null,
    expanded: false,
    history: [],
  };

  const el = {
    expression: document.getElementById('expression'),
    result: document.getElementById('result'),
    error: document.getElementById('error'),
    toggleFull: document.getElementById('toggle-full'),
    history: document.getElementById('history'),
    clearHistory: document.getElementById('clear-history'),
    themeToggle: document.getElementById('theme-toggle'),
  };

  // ---------------------------------------------------------------- хранилище
  function storageGet(key) {
    try { return window.localStorage.getItem(key); } catch (e) { return null; }
  }

  function storageSet(key, value) {
    try { window.localStorage.setItem(key, value); } catch (e) { /* хранилище недоступно */ }
  }

  // ------------------------------------------------------------------ дисплей
  function renderExpression() {
    el.expression.textContent = state.expression === '' ? '0' : state.expression;
    el.expression.scrollLeft = el.expression.scrollWidth;
  }

  function showError(message) {
    el.error.textContent = message;
  }

  function clearError() {
    el.error.textContent = '';
  }

  function clearResult() {
    state.lastResult = null;
    state.expanded = false;
    el.result.textContent = '';
    el.result.classList.remove('expanded');
    el.toggleFull.hidden = true;
  }

  function renderResult() {
    const data = state.lastResult;
    if (!data) { return; }
    const prefix = data.approximate ? '≈ ' : '';
    const needsToggle = data.full.length > LONG_RESULT_LENGTH && data.full !== data.result;
    el.result.textContent = prefix + (state.expanded ? data.full : data.result);
    el.result.classList.toggle('expanded', state.expanded);
    el.toggleFull.hidden = !needsToggle;
    el.toggleFull.textContent = state.expanded ? 'Свернуть' : 'Показать полностью';
  }

  // ------------------------------------------------------------------- ввод
  function currentNumber() {
    const match = state.expression.match(/[0-9.]+$/);
    return match ? match[0] : '';
  }

  // Новый ввод после «=» начинает новое выражение
  function startNewIfNeeded() {
    if (state.justCalculated) {
      state.expression = '';
      state.justCalculated = false;
      clearResult();
    }
  }

  function addDigit(digit) {
    startNewIfNeeded();
    if (currentNumber().length >= MAX_NUMBER_LENGTH) {
      showError('Слишком длинное число');
      return;
    }
    state.expression += digit;
  }

  function addDot() {
    startNewIfNeeded();
    const number = currentNumber();
    if (number.includes('.')) { return; }
    if (number.length >= MAX_NUMBER_LENGTH) {
      showError('Слишком длинное число');
      return;
    }
    state.expression += number === '' ? '0.' : '.';
  }

  function addOperator(operator) {
    // После «=» операция продолжает вычисление с предыдущим результатом
    if (state.justCalculated) {
      if (state.lastPlain.replace('-', '').length > MAX_NUMBER_LENGTH) {
        showError('Слишком длинное число');
        return;
      }
      state.expression = state.lastPlain;
      state.justCalculated = false;
      clearResult();
    }

    const expression = state.expression;
    const last = expression.slice(-1);

    if (operator === '%') {
      if (/[0-9)%]$/.test(expression)) { state.expression += '%'; }
      return;
    }

    if (expression === '') {
      if (operator === '-') { state.expression = '-'; }
      return;
    }
    if (expression === '-') { return; }

    if ('+-*/^'.includes(last)) {
      if (operator === '-' && '*/^'.includes(last)) {
        state.expression += operator; // унарный минус: 2*-3
      } else {
        state.expression = expression.slice(0, -1) + operator; // замена оператора
      }
    } else if (last === '(') {
      if (operator === '-') { state.expression += operator; }
    } else {
      state.expression += operator;
    }
  }

  function addFunction(name) {
    startNewIfNeeded();
    state.expression += name + '(';
  }

  function addParen(paren) {
    startNewIfNeeded();
    state.expression += paren;
  }

  function backspace() {
    if (state.justCalculated) {
      state.justCalculated = false;
      clearResult();
    }
    state.expression = state.expression.slice(0, -1);
  }

  function clearAll() {
    state.expression = '';
    state.justCalculated = false;
    clearResult();
  }

  // ------------------------------------------------------- предварительная проверка
  function validateExpression(expression) {
    if (expression.trim() === '') { return 'Введите выражение'; }
    if (/[^0-9+\-*/^%().a-zA-Z\s]/.test(expression)) { return 'Ошибка: недопустимые символы'; }

    let depth = 0;
    for (const char of expression) {
      if (char === '(') { depth += 1; }
      if (char === ')') { depth -= 1; }
      if (depth < 0) { return 'Ошибка: непарные скобки'; }
    }
    if (depth !== 0) { return 'Ошибка: непарные скобки'; }

    const numbers = expression.match(/[0-9.]+/g) || [];
    if (numbers.some(function (n) { return n.length > MAX_NUMBER_LENGTH; })) {
      return 'Слишком длинное число';
    }
    return '';
  }

  // ------------------------------------------------------------------ вычисление
  async function calculate() {
    clearError();
    const expression = state.expression;
    const problem = validateExpression(expression);
    if (problem) {
      showError(problem);
      return;
    }

    try {
      const response = await fetch('/calculate', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ expression: expression }),
      });
      const data = await response.json().catch(function () { return null; });

      if (!response.ok || !data || data.error) {
        clearResult();
        showError((data && data.error) || 'Ошибка: не удалось вычислить выражение');
        return;
      }

      state.lastResult = data;
      state.lastPlain = data.full;
      state.expanded = false;
      state.justCalculated = true;
      renderResult();
      addToHistory(expression, (data.approximate ? '≈ ' : '') + data.result);
    } catch (e) {
      clearResult();
      showError('Ошибка: нет связи с сервером');
    }
  }

  // ---------------------------------------------------------------------- история
  function renderHistory() {
    el.history.textContent = '';
    if (state.history.length === 0) {
      const empty = document.createElement('li');
      empty.className = 'history__empty';
      empty.textContent = 'Пока пусто';
      el.history.appendChild(empty);
      return;
    }
    state.history.forEach(function (item) {
      const li = document.createElement('li');
      const button = document.createElement('button');
      button.type = 'button';
      button.className = 'history__item';
      button.setAttribute('data-ui', '');
      button.textContent = item.expression + ' = ' + item.result;
      button.addEventListener('click', function () {
        state.expression = item.expression;
        state.justCalculated = false;
        clearResult();
        clearError();
        renderExpression();
      });
      li.appendChild(button);
      el.history.appendChild(li);
    });
  }

  function addToHistory(expression, result) {
    state.history.unshift({ expression: expression, result: result });
    state.history = state.history.slice(0, MAX_HISTORY);
    storageSet('smartCalcHistory', JSON.stringify(state.history));
    renderHistory();
  }

  function loadHistory() {
    try {
      const saved = JSON.parse(storageGet('smartCalcHistory') || '[]');
      if (Array.isArray(saved)) { state.history = saved.slice(0, MAX_HISTORY); }
    } catch (e) {
      state.history = [];
    }
    renderHistory();
  }

  // ------------------------------------------------------------------------ тема
  function applyTheme(theme) {
    document.documentElement.setAttribute('data-theme', theme);
    storageSet('smartCalcTheme', theme);
  }

  function initTheme() {
    const saved = storageGet('smartCalcTheme');
    const prefersDark = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
    applyTheme(saved || (prefersDark ? 'dark' : 'light'));
  }

  // ---------------------------------------------------------------- обработчики
  function handleInput(type, value) {
    clearError();
    switch (type) {
      case 'digit': addDigit(value); break;
      case 'dot': addDot(); break;
      case 'op': addOperator(value); break;
      case 'func': addFunction(value); break;
      case 'paren': addParen(value); break;
      case 'action':
        if (value === 'clear') { clearAll(); }
        if (value === 'backspace') { backspace(); }
        if (value === 'equals') { calculate(); }
        break;
      default: break;
    }
    renderExpression();
  }

  // Клик по кнопке добавляет символ в выражение
  document.querySelector('.calc').addEventListener('click', function (event) {
    const button = event.target.closest('button[data-type]');
    if (!button) { return; }
    handleInput(button.dataset.type, button.dataset.value);
    button.blur(); // чтобы Enter на клавиатуре вычислял, а не нажимал кнопку повторно
  });

  // Клавиатура дублирует кнопки
  document.addEventListener('keydown', function (event) {
    if (event.ctrlKey || event.metaKey || event.altKey) { return; }
    if (event.target.closest && event.target.closest('[data-ui]')) { return; }

    const key = event.key;
    if (/^[0-9]$/.test(key)) {
      handleInput('digit', key);
    } else if (key === '.' || key === ',') {
      handleInput('dot', '.');
    } else if (key.length === 1 && '+-*/^%'.includes(key)) {
      handleInput('op', key);
    } else if (key === '(' || key === ')') {
      handleInput('paren', key);
    } else if (key === 'Enter' || key === '=') {
      handleInput('action', 'equals');
    } else if (key === 'Backspace') {
      handleInput('action', 'backspace');
    } else if (key === 'Escape' || key === 'Delete') {
      handleInput('action', 'clear');
    } else {
      return;
    }
    event.preventDefault();
  });

  el.toggleFull.addEventListener('click', function () {
    state.expanded = !state.expanded;
    renderResult();
  });

  el.clearHistory.addEventListener('click', function () {
    state.history = [];
    storageSet('smartCalcHistory', '[]');
    renderHistory();
  });

  el.themeToggle.addEventListener('click', function () {
    const current = document.documentElement.getAttribute('data-theme');
    applyTheme(current === 'dark' ? 'light' : 'dark');
  });

  initTheme();
  loadHistory();
  renderExpression();
})();
