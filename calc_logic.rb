# frozen_string_literal: true

require 'bigdecimal'
require 'bigdecimal/math'
require 'strscan'

# Модуль с математической логикой «Умного калькулятора» (без интерфейса).
#
# Выражение разбирается собственным парсером (рекурсивный спуск),
# встроенные интерпретаторы (eval и аналоги) не используются.
# Все вычисления выполняются на BigDecimal, а не на Float.
#
# Грамматика (от низшего приоритета к высшему):
#   выражение := слагаемое (('+' | '-') слагаемое)*
#   слагаемое := унарное (('*' | '/') унарное)*
#   унарное   := ('-' | '+') унарное | степень
#   степень   := постфикс ['^' унарное]        (правоассоциативная)
#   постфикс  := первичное ('%')*
#   первичное := число | '(' выражение ')' | функция '(' выражение ')'
module CalcLogic
  # Ошибка, текст которой безопасно показывать пользователю.
  class CalcError < StandardError; end

  MAX_NUMBER_LENGTH     = 16    # максимальная длина вводимого числа (с дробной частью)
  MAX_EXPRESSION_LENGTH = 500   # защита от слишком длинных выражений
  DECIMAL_PLACES        = 10    # округление результата
  INTERNAL_PRECISION    = 40    # значащих цифр во внутренних вычислениях
  MAX_INT_EXPONENT      = 10_000
  MAX_DIGITS            = 20_000
  SCIENTIFIC_LIMIT      = BigDecimal('1e15') # больше этого значения - экспоненциальная запись
  PERCENT               = BigDecimal('0.01')
  FUNCTIONS             = %w[sin cos tan cot ln].freeze

  module_function

  # Главная точка входа: принимает строку, возвращает Hash:
  #   result      - строка для показа (для больших чисел в экспоненциальной записи)
  #   full        - полная запись числа без экспоненты
  #   approximate - true, если результат округлён (периодическая дробь и т.п.)
  def calculate(expression)
    text = expression.to_s.strip
    raise CalcError, 'Ошибка: пустое выражение' if text.empty?
    raise CalcError, 'Ошибка: слишком длинное выражение' if text.length > MAX_EXPRESSION_LENGTH

    tokens = tokenize(text)
    check_parentheses(tokens)
    tree = Parser.new(tokens).parse
    format_result(evaluate(tree))
  end

  # ---------------------------------------------------------------------------
  # 1. Лексер: строка -> список токенов
  # ---------------------------------------------------------------------------
  def tokenize(text)
    tokens = []
    scanner = StringScanner.new(text)
    until scanner.eos?
      next if scanner.skip(/\s+/)

      if (number = scanner.scan(/\d+(?:\.\d*)?|\.\d+/))
        raise CalcError, 'Слишком длинное число' if number.length > MAX_NUMBER_LENGTH

        tokens << [:num, normalize_number(number)]
      elsif (name = scanner.scan(/[A-Za-z]+/))
        name = name.downcase
        raise CalcError, "Ошибка: неизвестная функция «#{name}»" unless FUNCTIONS.include?(name)

        tokens << [:func, name]
      elsif (operator = scanner.scan(%r{[+\-*/^%]}))
        tokens << [:op, operator]
      elsif (paren = scanner.scan(/[()]/))
        tokens << [:paren, paren]
      else
        raise CalcError, "Ошибка: недопустимый символ «#{scanner.getch}»"
      end
    end
    tokens
  end

  # ".5" -> "0.5", "5." -> "5"
  def normalize_number(number)
    number = "0#{number}" if number.start_with?('.')
    number = number.chomp('.')
    number
  end

  # Проверка парности скобок до вычисления.
  def check_parentheses(tokens)
    depth = 0
    tokens.each do |type, value|
      next unless type == :paren

      depth += value == '(' ? 1 : -1
      raise CalcError, 'Ошибка: непарные скобки' if depth.negative?
    end
    raise CalcError, 'Ошибка: непарные скобки' unless depth.zero?
  end

  # ---------------------------------------------------------------------------
  # 2. Парсер: токены -> дерево выражения
  # ---------------------------------------------------------------------------
  class Parser
    def initialize(tokens)
      @tokens = tokens
      @pos = 0
    end

    def parse
      node = parse_expression
      raise CalcError, 'Ошибка: некорректное выражение' unless @pos == @tokens.length

      node
    end

    private

    def peek_operator?(*operators)
      token = @tokens[@pos]
      !token.nil? && token[0] == :op && operators.include?(token[1])
    end

    def advance
      token = @tokens[@pos]
      @pos += 1
      token
    end

    def close_paren!
      raise CalcError, 'Ошибка: непарные скобки' unless advance == [:paren, ')']
    end

    def parse_expression
      node = parse_term
      while peek_operator?('+', '-')
        operator = advance[1]
        node = [:bin, operator, node, parse_term]
      end
      node
    end

    def parse_term
      node = parse_unary
      while peek_operator?('*', '/')
        operator = advance[1]
        node = [:bin, operator, node, parse_unary]
      end
      node
    end

    def parse_unary
      if peek_operator?('-')
        advance
        [:neg, parse_unary]
      elsif peek_operator?('+')
        advance
        parse_unary
      else
        parse_power
      end
    end

    def parse_power
      base = parse_postfix
      return base unless peek_operator?('^')

      advance
      [:bin, '^', base, parse_unary]
    end

    def parse_postfix
      node = parse_primary
      while peek_operator?('%')
        advance
        node = [:pct, node]
      end
      node
    end

    def parse_primary
      token = advance
      raise CalcError, 'Ошибка: неполное выражение' if token.nil?

      type, value = token
      case type
      when :num
        [:num, BigDecimal(value)]
      when :func
        raise CalcError, "Ошибка: после #{value} нужна открывающая скобка" unless advance == [:paren, '(']

        argument = parse_expression
        close_paren!
        [:func, value, argument]
      when :paren
        raise CalcError, 'Ошибка: некорректное выражение' unless value == '('

        node = parse_expression
        close_paren!
        node
      else
        raise CalcError, 'Ошибка: некорректное выражение'
      end
    end
  end

  # ---------------------------------------------------------------------------
  # 3. Вычисление дерева
  # ---------------------------------------------------------------------------
  def evaluate(node)
    case node[0]
    when :num  then node[1]
    when :neg  then -evaluate(node[1])
    when :pct  then evaluate(node[1]) * PERCENT
    when :func then apply_function(node[1], evaluate(node[2]))
    when :bin  then evaluate_binary(node)
    else raise CalcError, 'Ошибка: некорректное выражение'
    end
  end

  def evaluate_binary(node)
    _, operator, left_node, right_node = node
    left = evaluate(left_node)

    # Проценты: 200 + 10% = 220 (прибавить 10%), 200 - 10% = 180
    right =
      if %w[+ -].include?(operator) && right_node[0] == :pct
        left * evaluate(right_node[1]) * PERCENT
      else
        evaluate(right_node)
      end

    case operator
    when '+' then left + right
    when '-' then left - right
    when '*' then left * right
    when '/'
      raise CalcError, 'Ошибка: деление на ноль' if right.zero?

      left.div(right, INTERNAL_PRECISION)
    when '^' then power(left, right)
    end
  end

  def power(base, exponent)
    return int_power_with_sign(base, exponent.to_i) if exponent.frac.zero?

    raise CalcError, 'Ошибка: отрицательное число нельзя возводить в дробную степень' if base.negative?

    if base.zero?
      raise CalcError, 'Ошибка: деление на ноль' unless exponent.positive?

      return BigDecimal(0)
    end

    argument = exponent * BigMath.log(base, INTERNAL_PRECISION)
    raise CalcError, 'Ошибка: результат слишком велик' if argument.abs > 2300

    BigMath.exp(argument, INTERNAL_PRECISION).round(20)
  end

  def int_power_with_sign(base, count)
    raise CalcError, 'Ошибка: слишком большая степень' if count.abs > MAX_INT_EXPONENT
    raise CalcError, 'Ошибка: результат слишком велик' if base.n_significant_digits * count.abs > MAX_DIGITS

    return BigDecimal(1) if count.zero?

    if count.negative?
      raise CalcError, 'Ошибка: деление на ноль' if base.zero?

      return BigDecimal(1).div(int_power(base, -count), INTERNAL_PRECISION)
    end

    int_power(base, count)
  end

  # Возведение в целую неотрицательную степень (точное, быстрое).
  def int_power(base, count)
    result = BigDecimal(1)
    factor = base
    while count.positive?
      result *= factor if count.odd?
      count >>= 1
      factor *= factor if count.positive?
    end
    result
  end

  def apply_function(name, argument)
    case name
    when 'sin' then sin_degrees(argument)
    when 'cos' then cos_degrees(argument)
    when 'tan' then tan_degrees(argument)
    when 'cot' then cot_degrees(argument)
    when 'ln'
      raise CalcError, 'Ошибка: ln(x) определён только для x > 0' unless argument.positive?

      BigMath.log(argument, INTERNAL_PRECISION).round(20)
    end
  end

  # Тригонометрия: углы задаются в градусах.
  def sin_degrees(degrees)
    angle = degrees % 360
    return BigDecimal(0) if (angle % 180).zero?
    return BigDecimal(1) if angle == 90
    return BigDecimal(-1) if angle == 270

    radians = (angle * BigMath.PI(INTERNAL_PRECISION)).div(BigDecimal(180), INTERNAL_PRECISION + 5)
    BigMath.sin(radians, INTERNAL_PRECISION).round(20)
  end

  def cos_degrees(degrees)
    sin_degrees(degrees + 90)
  end

  def tan_degrees(degrees)
    cosine = cos_degrees(degrees)
    raise CalcError, 'Ошибка: tan(x) не определён для этого угла' if cosine.zero?

    sin_degrees(degrees).div(cosine, INTERNAL_PRECISION).round(20)
  end

  def cot_degrees(degrees)
    sine = sin_degrees(degrees)
    raise CalcError, 'Ошибка: cot(x) не определён для этого угла' if sine.zero?

    cos_degrees(degrees).div(sine, INTERNAL_PRECISION).round(20)
  end

  # ---------------------------------------------------------------------------
  # 4. Форматирование результата
  # ---------------------------------------------------------------------------
  def format_result(value)
    raise CalcError, 'Ошибка: результат не является числом' unless value.finite?

    rounded = value.round(DECIMAL_PLACES)
    full = plain_string(rounded)
    display = rounded.abs > SCIENTIFIC_LIMIT ? scientific_string(rounded) : full
    { result: display, full: full, approximate: rounded != value }
  end

  # Обычная запись без экспоненты и без лишних нулей: 220, 0.3333333333
  def plain_string(number)
    return '0' if number.zero?

    number.to_s('F').sub(/\.0\z/, '')
  end

  # Экспоненциальная запись: 1.23e+16
  def scientific_string(number)
    sign, digits, _base, exponent = number.split
    power_of_ten = exponent - 1
    rest = digits[1..]
    mantissa = BigDecimal("#{digits[0]}.#{rest.empty? ? '0' : rest}").round(DECIMAL_PLACES)
    if mantissa >= 10
      mantissa /= 10
      power_of_ten += 1
    end
    "#{'-' if sign.negative?}#{plain_string(mantissa)}e#{power_of_ten.negative? ? '-' : '+'}#{power_of_ten.abs}"
  end
end
