module geo::shape

import geo::point

pub Shape :: enum {
    Circle { center: Point, r: f64 },
    Rect { min: Point, max: Point },
}
