local Linear, parent = torch.class('Linear', 'nn.Module')

function Linear:__init(inputSize, outputSize, magnitude)
   parent.__init(self)
   self.weight = torch.Tensor(outputSize, inputSize)
   self.feedback = torch.Tensor(outputSize, inputSize)
   self.gradWeight = torch.Tensor(outputSize, inputSize)
   self.backprop = false
   self.bias = torch.Tensor(outputSize)
   self.gradBias = torch.Tensor(outputSize)
   self.mag = magnitude or 0
   self:reset()
end

function Linear:reset(stdv)
   if stdv then
      stdv = stdv * math.sqrt(3)
   else
      stdv = 1./math.sqrt(self.weight:size(2))
   end
   if nn.oldSeed then
      for i=1,self.weight:size(1) do
         self.weight:select(1, i):apply(function()
            return torch.uniform(-stdv, stdv)
         end)
      end
      if self.bias then
         for i=1,self.bias:nElement() do
            self.bias[i] = torch.uniform(-stdv, stdv)
         end
      end
   else
      self.weight:uniform(-stdv, stdv)
      if self.bias then self.bias:uniform(-stdv, stdv) end
   end
   
   if self.mag == 0 then
      self.feedback:copy(self.weight)
      self.mag = stdv
   else
      self.feedback:uniform(-self.mag,self.mag)
   end
   
   return self
end

function Linear:updateOutput(input)
   if input:dim() == 1 then
      self.output:resize(self.weight:size(1))
      if self.bias then self.output:copy(self.bias) else self.output:zero() end
      self.output:addmv(1, self.weight, input)
   elseif input:dim() == 2 then
      local nframe = input:size(1)
      local nElement = self.output:nElement()
      self.output:resize(nframe, self.weight:size(1))
      if self.output:nElement() ~= nElement then
         self.output:zero()
      end
      self.addBuffer = self.addBuffer or input.new()
      if self.addBuffer:nElement() ~= nframe then
         self.addBuffer:resize(nframe):fill(1)
      end
      self.output:addmm(0, self.output, 1, input, self.weight:t())
      if self.bias then self.output:addr(1, self.addBuffer, self.bias) end
   else
      error('input must be vector or matrix')
   end

   return self.output
end

function Linear:updateGradInput(input, gradOutput)
   if self.gradInput then
      
      local nElement = self.gradInput:nElement()
      self.gradInput:resizeAs(input)
      if self.gradInput:nElement() ~= nElement then
         self.gradInput:zero()
      end
      if self.backprop==true then
        if input:dim() == 1 then
           self.gradInput:addmv(0, 1, self.weight:t(), gradOutput)
        elseif input:dim() == 2 then
           self.gradInput:addmm(0, 1, gradOutput, self.weight)
        end
      else
        if input:dim() == 1 then
           self.gradInput:addmv(0, 1, self.feedback:t(), gradOutput)
        elseif input:dim() == 2 then
           self.gradInput:addmm(0, 1, gradOutput, self.feedback)
        end
      end

      return self.gradInput
   end
end

function Linear:accGradParameters(input, gradOutput, scale)
   scale = scale or 1
   if input:dim() == 1 then
      self.gradWeight:addr(scale, gradOutput, input)
      self.gradBias:add(scale, gradOutput)
   elseif input:dim() == 2 then
      self.gradWeight:addmm(scale, gradOutput:t(), input)
      self.gradBias:addmv(scale, gradOutput:t(), self.addBuffer)
   end
end

-- we do not need to accumulate parameters when sharing
Linear.sharedAccUpdateGradParameters = Linear.accUpdateGradParameters

function Linear:clearState()
   if self.addBuffer then self.addBuffer:set() end
   return parent.clearState(self)
end

function Linear:__tostring__()
  return torch.type(self) ..
      string.format('(%d -> %d), mag=%.3f', self.weight:size(2), self.weight:size(1), self.mag)
end
