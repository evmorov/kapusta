class TreeNode
  def initialize(val, left, right)
    @val = val
    @left = left
    @right = right
  end
  def val
    @val
  end
  def left
    @left
  end
  def right
    @right
  end
end
class BSTIterator
  def initialize(root)
    @stack = []
    self.push_left(root)
  end
  def push_left(node)
    n = node
    while n
      stack = @stack
      stack.push(n)
      n = n.left
    end
  end
  def next
    stack = @stack
    node = stack.pop
    self.push_left(node.right)
    node.val
  end
  def has_next?
    stack = @stack
    !stack.empty?
  end
end
root = TreeNode.new(7, TreeNode.new(3, nil, nil), TreeNode.new(15, TreeNode.new(9, nil, nil), TreeNode.new(20, nil, nil)))
it = BSTIterator.new(root)
p it.next
p it.next
p it.has_next?
p it.next
p it.has_next?
p it.next
p it.next
p it.has_next?
