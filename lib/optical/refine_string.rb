module Optical
  module StringExensions
    refine String do
      def mid_truncate(len)
        return self.clone if size <= len
        return self[0...len] unless len > 4
        mid = len / 2.0
        (result = dup)[(mid - 1.5).floor...(1.5 - mid).floor] = ''
        result
      end
    end
  end
end
