class AllowNullPayjpChargeIdInPayments < ActiveRecord::Migration[6.1]
def change
    # payjp_charge_id を空（NULL）でも保存できるように変更する
    change_column_null :payments, :payjp_charge_id, true
  end
end
