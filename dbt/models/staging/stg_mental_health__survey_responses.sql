with source as (

    select * from {{ ref('mental_health_survey') }}

),

renamed as (

    select
        -- Deterministic surrogate key: the same row gets the same id on every
        -- run (row_number() over () with no ORDER BY doesn't guarantee that).
        -- Hashing every raw column also makes the unique test on this key a
        -- duplicate-row check.
        md5(concat_ws('|',
            "Gender", "Age", "Education_Level", "Employment_Status", "Depression_Type",
            "Symptoms", "Low_Energy", "Low_SelfEsteem", "Search_Depression_Online",
            "Worsening_Depression", "Your overeating level", "How many times you eat ",
            "SocialMedia_Hours", "SocialMedia_WhileEating", "Sleep_Hours", "Nervous_Level",
            "Depression_Score", "Coping_Methods", "Self_Harm", "Mental_Health_Support",
            "Suicide_Attempts"
        )) as response_id,
        cast("Gender" as integer)                      as gender,
        cast("Age" as integer)                          as age,
        cast("Education_Level" as integer)              as education_level,
        cast("Employment_Status" as integer)            as employment_status,
        cast("Depression_Type" as integer)              as depression_type,
        cast("Symptoms" as integer)                     as symptoms,
        cast("Low_Energy" as integer)                   as low_energy,
        cast("Low_SelfEsteem" as integer)                as low_self_esteem,
        cast("Search_Depression_Online" as integer)     as search_depression_online,
        cast("Worsening_Depression" as integer)         as worsening_depression,
        cast("Your overeating level" as integer)        as overeating_level,
        cast("How many times you eat " as integer)      as eating_frequency,
        cast("SocialMedia_Hours" as integer)             as social_media_hours,
        cast("SocialMedia_WhileEating" as integer)       as social_media_while_eating,
        cast("Sleep_Hours" as integer)                   as sleep_hours,
        cast("Nervous_Level" as integer)                 as nervous_level,
        cast("Depression_Score" as integer)              as depression_score,
        cast("Coping_Methods" as integer)                as coping_methods,
        cast("Self_Harm" as integer)                     as self_harm,
        cast("Mental_Health_Support" as integer)         as mental_health_support,
        cast("Suicide_Attempts" as integer)              as suicide_attempts
    from source

)

select * from renamed
