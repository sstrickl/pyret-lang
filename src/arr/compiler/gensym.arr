#lang pyret

provide {
  make-name: make-name,
  make-label-sequence: make-label-sequence
} end
provide-types {
  Label: Label
}

type Label = { get :: ( -> Number) }

fun make-label-sequence(init :: Number) -> ( -> Label):
  var next = init
  lam():
    var value = nothing
    {
      get: lam():
          if value == nothing:
            value := next
            next := next + 1
            value
          else:
            value
          end
      end}
  end
end

make-name = block:
  var gensym-counter = 0
  lam(base):
    gensym-counter := 1 + gensym-counter
    base + (tostring(gensym-counter))
  end
end

