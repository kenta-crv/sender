class AddTemplateVarsToCustomers < ActiveRecord::Migration[6.1]
  def change
    add_column :customers, :template_vars, :text
  end
end
