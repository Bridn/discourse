class AddThemes < ActiveRecord::Migration
  def up
    rename_table :site_customizations, :themes

    add_column :themes, :user_selectable, :bool, null: false, default: false
    add_column :themes, :hidden, :bool, null: false, default: false
    add_column :themes, :color_scheme_id, :integer

    create_table :child_themes do |t|
      t.integer :parent_theme_id
      t.integer :child_theme_id
      t.timestamps
    end

    add_index :child_themes, [:parent_theme_id, :child_theme_id], unique: true
    add_index :child_themes, [:child_theme_id, :parent_theme_id], unique: true

    execute <<SQL
    INSERT INTO child_themes(parent_theme_id, child_theme_id, created_at, updated_at)
    SELECT -1, id, created_at, updated_at
    FROM themes WHERE enabled
SQL

    remove_column :themes, :enabled

  end

  def down
    raise IrriversibleMigration
  end
end
