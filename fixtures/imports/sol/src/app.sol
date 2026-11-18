module app

import std::io
import geo::shape

main :: (init: Init) -> ()! {
    $io :: init.io
    $io |> println("{}", Shape::Circle{ center = Point{ x = 0.0, y = 0.0 }, r = 2.0 })!
    return
}
