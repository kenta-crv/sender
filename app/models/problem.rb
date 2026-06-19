class Problem < ApplicationRecord
  # photo カラムに ImagesUploader をマウントします
  mount_uploader :photo, ImagesUploader
end