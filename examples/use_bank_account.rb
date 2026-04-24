# frozen_string_literal: true

require 'bundler/setup'
require 'kapusta'

Kapusta.require('./bank-account', relative_to: __FILE__)

account = BankAccount.new('Ada', 100)
account.deposit(50)
account.withdraw(30)

puts "Owner:   #{account.owner}"
puts "Balance: #{account.balance}"
