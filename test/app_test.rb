# frozen_string_literal: true

ENV['APP_ENV'] = 'test'
ENV['RACK_ENV'] = 'test'

require 'minitest/autorun'
require 'rack/test'
require 'json'
require_relative '../app'

# Тесты веб-сервера: маршруты GET / и POST /calculate.
class AppTest < Minitest::Test
  include Rack::Test::Methods

  def app
    SmartCalcApp
  end

  def post_expression(expression)
    post '/calculate', { expression: expression }.to_json, 'CONTENT_TYPE' => 'application/json'
  end

  def json_body
    JSON.parse(last_response.body)
  end

  def test_index_page_is_served
    get '/'
    assert last_response.ok?
    assert_includes last_response.body, 'Умный калькулятор'
  end

  def test_calculate_returns_result
    post_expression('2 + 3 * (4 - 1)')
    assert last_response.ok?
    assert_equal '11', json_body['result']
    assert_equal false, json_body['approximate']
  end

  def test_calculate_marks_approximate_result
    post_expression('1 / 3')
    assert last_response.ok?
    assert_equal '0.3333333333', json_body['result']
    assert_equal true, json_body['approximate']
  end

  def test_division_by_zero_returns_readable_error
    post_expression('1 / 0')
    assert_equal 422, last_response.status
    assert_equal 'Ошибка: деление на ноль', json_body['error']
  end

  def test_empty_expression_returns_error
    post_expression('')
    assert_equal 422, last_response.status
    assert_equal 'Ошибка: пустое выражение', json_body['error']
  end

  def test_invalid_json_returns_400
    post '/calculate', 'это не json', 'CONTENT_TYPE' => 'application/json'
    assert_equal 400, last_response.status
    assert_equal 'Ошибка: некорректный запрос', json_body['error']
  end

  def test_missing_expression_field
    post '/calculate', {}.to_json, 'CONTENT_TYPE' => 'application/json'
    assert_equal 422, last_response.status
    assert json_body['error']
  end
end
