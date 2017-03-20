class ChildTheme < ActiveRecord::Base
  belongs_to :parent_theme, class_name: 'Theme'
  belongs_to :child_theme, class_name: 'Theme'
end
