module SignalHarvest
  SCREEN_W = 1280
  TARGET_SCORE = 36
  def self.cell_width(columns)
    SCREEN_W / columns
  end
  def self.win?(score)
    score >= TARGET_SCORE
  end
end
p SignalHarvest.cell_width(32)
p SignalHarvest.win?(40)
p SignalHarvest.win?(12)
