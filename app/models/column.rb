class Column < ApplicationRecord
  #mount_uploader :file, ImagesUploader

  def to_meta_tags
  {
    title: title,
    keyword: keyword,
    description: description
  }
  end
  def approved?
    status == "approved"
  end
end
