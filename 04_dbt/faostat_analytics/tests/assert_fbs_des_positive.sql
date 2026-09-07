select
    area_name,
    year,
    des_kcal_cap_day,
    flag_des

from {{ ref('fct_food_security') }}
where
    des_kcal_cap_day is not null
    and des_kcal_cap_day <= 0