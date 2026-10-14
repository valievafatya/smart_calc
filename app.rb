# frozen_string_literal: true

require 'sinatra/base'
require 'json'
require_relative 'calc_logic'

# Веб-сервер «Умного калькулятора» на Sinatra.
#   GET  /          - страница с интерфейсом
#   POST /calculate - принимает JSON {"expression": "..."} и возвращает JSON
#                     с результатом или с сообщением об ошибке
class SmartCalcApp < Sinatra::Base
  set :port, 4567

  get '/' do
    erb :index
  end

  post '/calculate' do
    content_type :json
    expression = read_expression

    begin
      CalcLogic.calculate(expression).to_json
    rescue CalcLogic::CalcError => e
      halt 422, { error: e.message }.to_json
    rescue StandardError
      # Служебные подробности пользователю не показываем - только понятный текст.
      halt 500, { error: 'Ошибка: не удалось вычислить выражение' }.to_json
    end
  end

  helpers do
    # Достаёт выражение из тела запроса; при неверном JSON отвечает ошибкой 400.
    def read_expression
      payload = JSON.parse(request.body.read)
      payload.is_a?(Hash) ? payload['expression'].to_s : ''
    rescue JSON::ParserError
      halt 400, { error: 'Ошибка: некорректный запрос' }.to_json
    end
  end

  run! if app_file == $PROGRAM_NAME
end
