unless Theme.where(id: -1).exists?
  Theme.seed do |t|
    t.id = -1
    t.name = "Default"
    t.key = "7e202ef2-56d7-47d5-98d8-a9c8d15e57dd"
    t.user_id = -1
  end
end
