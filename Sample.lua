local function setTexForIcon(tex, ix)
    tex:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    local coords={
      [1]={0,0.25,0,0.25},  -- Star
      [2]={0.25,0.5,0,0.25},-- Circle
      [3]={0.5,0.75,0,0.25},-- Diamond
      [4]={0.75,1,0,0.25},  -- Triangle
      [5]={0,0.25,0.25,0.5},-- Moon
      [6]={0.25,0.5,0.25,0.5},-- Square
      [7]={0.5,0.75,0.25,0.5},-- Cross
      [8]={0.75,1,0.25,0.5},-- Skull
    }
    local c = coords[ix] or coords[1]
    tex:SetTexCoord(c[1],c[2],c[3],c[4])
  end