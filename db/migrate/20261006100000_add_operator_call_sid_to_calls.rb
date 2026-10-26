class AddOperatorCallSidToCalls < ActiveRecord::Migration[6.1]
  def change
    add_column :calls, :operator_call_sid, :string
  end
end
