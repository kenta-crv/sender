class Contract < ApplicationRecord
  #has_many :comments, dependent: :destroy
  validate :company_must_include_kaisha
  private

  def company_must_include_kaisha
   unless company&.include?("会社") || company&.include?("組合")
    errors.add(:company, 'には「敬称」を含める必要があります')
   end
  end
end
