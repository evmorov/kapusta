class BankAccount
  def initialize(owner, balance)
    @owner = owner
    @balance = balance
  end
  def owner
    @owner
  end
  def balance
    @balance
  end
  def deposit(amount)
    @balance += amount
    self
  end
  def withdraw(amount)
    @balance -= amount
    self
  end
end
