# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../calc_logic'

# Юнит-тесты модуля CalcLogic: точность, ошибочные случаи, приоритет операций.
class CalcLogicTest < Minitest::Test
  def calc(expression)
    CalcLogic.calculate(expression)
  end

  def assert_result(expected, expression)
    assert_equal expected, calc(expression)[:result], "выражение: #{expression}"
  end

  def assert_error(message, expression)
    error = assert_raises(CalcLogic::CalcError, "выражение: #{expression}") { calc(expression) }
    assert_equal message, error.message
  end

  # --- точность и периодические дроби ---------------------------------------

  def test_decimal_precision_is_exact
    assert_result '0.3', '0.1 + 0.2'
    refute calc('0.1 + 0.2')[:approximate]
    assert_result '0.3', '0.1 * 3'
  end

  def test_periodic_fraction_is_rounded_and_marked
    result = calc('1 / 3')
    assert_equal '0.3333333333', result[:result]
    assert result[:approximate]
  end

  def test_exact_division
    assert_result '2.5', '10 / 4'
    refute calc('10 / 4')[:approximate]
  end

  # --- приоритет операций и скобки -------------------------------------------

  def test_operator_priority
    assert_result '11', '2 + 3 * (4 - 1)'
    assert_result '14', '2 + 3 * 4'
    assert_result '20', '(2 + 3) * 4'
  end

  def test_power_is_right_associative_and_unary_minus
    assert_result '512', '2 ^ 3 ^ 2'
    assert_result '-4', '-2 ^ 2'
    assert_result '0.25', '2 ^ -2'
    assert_result '1024', '2 ^ 10'
  end

  def test_fractional_power
    result = calc('2 ^ 0.5')
    assert_equal '1.4142135624', result[:result]
    assert result[:approximate]
    assert_result '3', '9 ^ 0.5'
  end

  def test_negative_base_with_fractional_power_is_error
    assert_error 'Ошибка: отрицательное число нельзя возводить в дробную степень', '(-8) ^ 0.5'
  end

  # --- проценты ----------------------------------------------------------------

  def test_percent
    assert_result '220', '200 + 10%'
    assert_result '180', '200 - 10%'
    assert_result '20', '200 * 10%'
    assert_result '0.1', '10%'
  end

  # --- деление на ноль ------------------------------------------------------------

  def test_division_by_zero
    assert_error 'Ошибка: деление на ноль', '5 / 0'
    assert_error 'Ошибка: деление на ноль', '5 / (3 - 3)'
    assert_error 'Ошибка: деление на ноль', '0 ^ -1'
  end

  # --- функции ---------------------------------------------------------------------

  def test_trigonometry_in_degrees
    assert_result '0.5', 'sin(30)'
    assert_result '0.5', 'cos(60)'
    assert_result '1', 'sin(90)'
    assert_result '0', 'cos(90)'
    assert_result '0', 'sin(180)'
    assert_result '1', 'tan(45)'
    assert_result '1', 'cot(45)'
    assert_result '-1', 'sin(270)'
  end

  def test_trigonometry_domain
    assert_error 'Ошибка: tan(x) не определён для этого угла', 'tan(90)'
    assert_error 'Ошибка: cot(x) не определён для этого угла', 'cot(0)'
    assert_error 'Ошибка: cot(x) не определён для этого угла', 'cot(180)'
  end

  def test_natural_logarithm
    assert_result '0', 'ln(1)'
    result = calc('ln(2)')
    assert_equal '0.6931471806', result[:result]
    assert result[:approximate]
  end

  def test_logarithm_domain
    assert_error 'Ошибка: ln(x) определён только для x > 0', 'ln(0)'
    assert_error 'Ошибка: ln(x) определён только для x > 0', 'ln(0 - 5)'
  end

  # --- некорректный ввод --------------------------------------------------------------

  def test_empty_expression
    assert_error 'Ошибка: пустое выражение', ''
    assert_error 'Ошибка: пустое выражение', '   '
  end

  def test_unbalanced_parentheses
    assert_error 'Ошибка: непарные скобки', '(1 + 2'
    assert_error 'Ошибка: непарные скобки', '1 + 2)'
    assert_error 'Ошибка: непарные скобки', ')1 + 2('
  end

  def test_syntax_errors
    assert_raises(CalcLogic::CalcError) { calc('2 +') }
    assert_raises(CalcLogic::CalcError) { calc('5 5') }
    assert_raises(CalcLogic::CalcError) { calc('()') }
    assert_raises(CalcLogic::CalcError) { calc('* 3') }
    assert_raises(CalcLogic::CalcError) { calc('sin 30') }
  end

  def test_invalid_characters_and_unknown_functions
    assert_raises(CalcLogic::CalcError) { calc('2 $ 3') }
    assert_raises(CalcLogic::CalcError) { calc('foo(1)') }
    # Код не исполняется - это просто неизвестная функция
    assert_raises(CalcLogic::CalcError) { calc('system("ls")') }
    assert_raises(CalcLogic::CalcError) { calc('`ls`') }
  end

  # --- большие числа ----------------------------------------------------------------------

  def test_number_length_limit
    assert_equal '1234567890123456', calc('1234567890123456')[:full]
    assert_error 'Слишком длинное число', '12345678901234567'
    assert_error 'Слишком длинное число', '0.12345678901234567'
  end

  def test_big_results_use_scientific_notation
    result = calc('1230000000000000 * 10')
    assert_equal '1.23e+16', result[:result]
    assert_equal '12300000000000000', result[:full]
    refute_includes calc('1000000000000000')[:result], 'e'
  end

  def test_huge_numbers_are_exact
    result = calc('9999999999999999 * 9999999999999999')
    assert_equal '99999999999999980000000000000001', result[:full]
  end

  def test_too_large_power_is_rejected
    assert_raises(CalcLogic::CalcError) { calc('9999999999999999 ^ 9999') }
  end
end
