class CreateSites < ActiveRecord::Migration
  def change
    create_table :sites do |t|
      t.string  :type
      t.string  :name
      t.float   :price
      t.string  :url
      t.float  :latitude
      t.float  :longitude
      t.json    :meta

      t.timestamps null: false
    end
  end
end
