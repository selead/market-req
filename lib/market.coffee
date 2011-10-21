###
Market for crowd requests
###

redis = require "redis"

exports.version = "0.1.1"

###
Class for connect to market and manage tokens
###
class MarketClient
  constructor: (client) ->
    @client = client || redis.createClient()

  ###
  Add new token pair, hour is optional, default - current hour
  ###
  addToken:  (service, token, token_secret, requests, hour=null) ->
    hour ||= parseInt Date.now() /(60 * 60000)
    @client.zadd "mkt:#{service}:#{hour}", requests, "#{token} #{token_secret}"
    @client.hincrby "mkt:stat:#{service}:#{hour}", "total", requests

  ###
  Get statistics by service and hour

  fn callback assept error as first parameter and stat object as second
  stat object contain fields:
      total                    total token pairs x requests added
      used                     tokens fetched from market
      overflow                 number of overflow requests to market
      tokens_over              number of requests, that could not be proceed (tokens missed for this hour
      fetch_requests           number of fetching requests
  ###
  getStatByHour: (service, hour, fn) ->
    hour ||= parseInt Date.now() /(60 * 60000)
    @client.hgetall "mkt:stat:#{service}:#{hour}", (err, dict) ->
      if !err
        dict.total ||= 0
        dict.fetch_requests ||= 0
        dict.used ||= 0
        dict.overflow ||= 0
        dict.tokens_over ||= 0
        fn null, dict
      else
        fn {msg: "error getting stat"}

  ###
  Utilize tokens from redis
  ###
  fetchTokens: (service, requests, hour, fn) ->
    if "function" == typeof hour
      fn = hour
      hour = null
    hour ||= parseInt Date.now() /(60 * 60000)
    key = "mkt:#{service}:#{hour}"
    statKey = "mkt:stat:#{service}:#{hour}"
    @client.hincrby statKey, "fetch_requests", 1

    @client.hget statKey, "total", (err, total) =>
      @client.hget statKey, "used", (err, used) =>
        if parseInt(used) >= parseInt(total) - 1
          @client.hincrby statKey, "overflow", 1
          fn {msg: "not enough tokens"}
        else
          @client.zrevrange key, 0, 100, "withscores", (err, data) =>
            if 0 == data.length
              @client.hincrby statKey, "tokens_over", 1
              return fn {msg: "tokens not found"}
            result = []
            found = 0
            while found < requests && 0 < data.length
              tokens = data.shift()
              reqValue = parseInt(data.shift()) || 0
              break if 0 == reqValue        # we not reach requested quantity, drop this!
              if found + reqValue < requests
                @client.zincrby key, -reqValue, tokens
                found += reqValue
              else
                delta = reqValue - (requests - found)
                @client.zadd key, delta, tokens
                reqValue -= delta
                found = requests
              result.push [tokens.split(" "), reqValue]
            if requests == found
              @client.hincrby statKey, "used", requests
              fn null, result
            else
              @client.hincrby statKey, "overflow", 1
              for r in result
                @client.zadd(key, r[1],  r[0].join " ") if r[1] > 0

              fn {msg: "not enough tokens"}


exports.createClient = (client) -> new MarketClient




