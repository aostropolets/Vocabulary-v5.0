-- Check if there are any known drug Brand names missed in the mapping:
-- This check allows to retrieve target brand names from manual mapping and brand names that correspond to the ingredients, mentioned in the source,
--- and compare them. Our aim is to reveal so called 'stable' brand names, when only one RxNorm brand corresponds to one ingredient/combination.
-- Three flags are used in the 'flag' field:
--- definite brand - in case when the source concepts contains a particular brand name
--- possible brand - when the brand is defined according to RxNorm hierarchy
--- no ing detected - in case when ingredient name in the source differs from the standard ingredient (typos, alternative spelling, etc.)
-- Following flags are used in the 'mapping' field:
--- correct mapping - in case when source and target brands are equal
--- review mapping - in case when source and target concept differ
-- The 'brand' field indicates brand names that correspond to the source ingredients.
--- If there are several brands for one ingredient/combination then 'Multiple brands' flag is used.
--- If there no RxNorm brand name corresponds to the ingredient then 'No brand' flag is used.

-- define brand names of target concepts:
WITH mapped_brand AS
    (SELECT DISTINCT c.concept_code,
           c.concept_name,
           c1.concept_name AS target_name,
           c1.vocabulary_id AS target_vocab,
           CASE WHEN c1.concept_class_id LIKE '%Brand%'
               THEN c2.concept_name END AS mapped_Brand
    FROM concept_relationship cr
    JOIN concept c ON c.concept_id = cr.concept_id_1
    JOIN concept c1 ON c1.concept_id = cr.concept_id_2
    JOIN concept_relationship cr2 ON cr.concept_id_2 = cr2.concept_id_1
    JOIN concept c2 ON c2.concept_id = cr2.concept_id_2
    WHERE cr.relationship_id = 'Maps to'
    AND cr.invalid_reason IS NULL
    AND c.vocabulary_id = 'HCPCS'
    AND c.domain_id = 'Drug'
    AND cr2.relationship_id = 'Has brand name'
    AND cr2.invalid_reason IS NULL
    ),

-- extract Brand names already present in source concepts:
definite_brand AS
    (SELECT c.concept_code AS hcpcs_code,
         c.concept_name AS hcpcs_name,
         'definite_brand' AS flag,
         cc.concept_name AS brand
          FROM concept c
    JOIN concept cc
          ON (UPPER (c.concept_name) LIKE '%(' || UPPER (cc.concept_name) || '%'
          OR UPPER (c.concept_name) LIKE '%' || UPPER (cc.concept_name) || '/%'
          OR UPPER (c.concept_name) LIKE '%, ' || UPPER (cc.concept_name) || ', %'
          OR UPPER (c.concept_name) LIKE '% ' || UPPER (cc.concept_name) || ' %'
          OR UPPER (c.concept_name) LIKE '% ' || UPPER (cc.concept_name))
    JOIN concept_relationship cr ON c.concept_id = cr.concept_id_1
    JOIN concept cc2 ON cc2.concept_id = cr.concept_id_2
    WHERE cc.vocabulary_id = 'RxNorm'
    AND cc.concept_class_id = 'Brand Name'
    AND cc.invalid_reason IS NULL
    AND c.vocabulary_id = 'HCPCS'
    AND c.domain_id = 'Drug'
    AND cr.relationship_id = 'Maps to'
    AND cr.invalid_reason IS NULL
    ),

-- extract precise ingredients:
precise_ing AS
    (SELECT c.concept_code AS hcpcs_code,
            c.concept_name AS hcpcs_name,
            cc.concept_id AS ing_id,
            cc.concept_name AS ingredient
    FROM concept c
    LEFT JOIN concept cc
            ON (UPPER (c.concept_name) LIKE '% ' || UPPER (cc.concept_name) || ' %'
            OR UPPER (c.concept_name) LIKE  '% ' || UPPER (cc.concept_name) || ',%'
            OR UPPER (c.concept_name) LIKE  '% ' || UPPER (cc.concept_name) || '/%'
            OR UPPER (c.concept_name) LIKE  '% ' || UPPER (cc.concept_name)
            OR UPPER (c.concept_name) LIKE  UPPER (cc.concept_name) || ' %'
            OR UPPER (c.concept_name) LIKE  UPPER (cc.concept_name) || ',%'
            OR UPPER (c.concept_name) LIKE  UPPER (cc.concept_name) || ';%'
            OR UPPER (c.concept_name) LIKE  UPPER (cc.concept_name) || '/%'
            OR UPPER (c.concept_name) LIKE  UPPER (cc.concept_name)
            OR UPPER (c.concept_name) LIKE '%/' || UPPER (cc.concept_name) || ' %'
            OR UPPER (c.concept_name) LIKE '%/ ' || UPPER (cc.concept_name) || ' %'
            OR UPPER (c.concept_name) LIKE '%/' || UPPER (cc.concept_name)
            OR UPPER (c.concept_name) LIKE '% ' || UPPER (cc.concept_name) || ' %'
            OR UPPER (c.concept_name) LIKE '% ' || UPPER (cc.concept_name))
    WHERE c.vocabulary_id = 'HCPCS'
    AND c.domain_id = 'Drug'
    AND cc.vocabulary_id = 'RxNorm'
    AND cc.concept_class_id IN ('Precise Ingredient')
    AND cc.invalid_reason IS NULL
    AND c.concept_code NOT IN (SELECT hcpcs_code FROM definite_brand)
    ),

-- convert precise ingredients into the respective ingredients:
precise_to_ing AS
    (SELECT hcpcs_code,
           hcpcs_name,
           a.concept_id_2 AS ing_id,
           c2.concept_name AS ingredient
    FROM precise_ing p
    JOIN concept_relationship a ON p.ing_id = a.concept_id_1
    JOIN concept c2 ON c2.concept_id = a.concept_id_2
    WHERE a.relationship_id = 'Form of'
    AND a.invalid_reason IS NULL
    AND c2.invalid_reason IS NULL
    ),

-- extract ingredient names:
hcpcs_ing AS
       (SELECT c.concept_code AS hcpcs_code,
               c.concept_name AS hcpcs_name,
               CASE WHEN LOWER(c.concept_name) LIKE '%estradiol%'
                        THEN '1548195'
                   WHEN LOWER(c.concept_name) LIKE '%aripiprazole%'
                       THEN '757688'
                    WHEN LOWER(c.concept_name) LIKE '%aprotonin%'
                       THEN '19000729'
                   WHEN LOWER(c.concept_name) LIKE '%melphalan%'
                       THEN '1301267'
                   ELSE cc.concept_id END AS ing_id,
               CASE WHEN LOWER(c.concept_name) LIKE '%estradiol%'
                       THEN 'estradiol'
                   WHEN LOWER(c.concept_name) LIKE '%aripiprazole%'
                       THEN 'aripiprazole'
                   WHEN LOWER(c.concept_name) LIKE '%aprotonin%'
                       THEN 'aprotinin'
                   WHEN LOWER(c.concept_name) LIKE '%melphalan%'
                       THEN 'melphalan'
                   ELSE cc.concept_name END AS ingredient
            FROM concept c
            LEFT JOIN concept cc
            ON (UPPER (c.concept_name) LIKE '% ' || UPPER (cc.concept_name) || ' %'
            OR UPPER (c.concept_name) LIKE  '% ' || UPPER (cc.concept_name) || ',%'
            OR UPPER (c.concept_name) LIKE  '% ' || UPPER (cc.concept_name) || '/%'
            OR UPPER (c.concept_name) LIKE  UPPER (cc.concept_name) || ' %'
            OR UPPER (c.concept_name) LIKE  UPPER (cc.concept_name) || ', %'
            OR UPPER (c.concept_name) LIKE  UPPER (cc.concept_name) || '/%'
            OR UPPER (c.concept_name) LIKE  UPPER (cc.concept_name) || ';%'
            OR UPPER (c.concept_name) LIKE  UPPER (cc.concept_name)
            OR UPPER (c.concept_name) LIKE '%/' || UPPER (cc.concept_name) || '%'
            OR UPPER (c.concept_name) LIKE '%/ ' || UPPER (cc.concept_name) || '%'
            OR UPPER (c.concept_name) LIKE '%/' || UPPER (cc.concept_name)
            OR UPPER (c.concept_name) LIKE '% ' || UPPER (cc.concept_name) || ' %'
            OR UPPER (c.concept_name) LIKE '% ' || UPPER (cc.concept_name))
       JOIN concept_relationship cr ON cc.concept_id = cr.concept_id_1
       WHERE c.vocabulary_id = 'HCPCS'
       AND c.domain_id = 'Drug'
       AND cc.vocabulary_id IN ('RxNorm')
       AND cc.concept_class_id IN ('Ingredient')
       AND cc.concept_name NOT IN ('lactate', 'calcium', 'acetate', 'sodium', 'sodium phosphate', 'sodium succinate', 'succinate',
                                         'magnesium', 'potassium', 'gluconate', 'citrate', 'pyrophosphate', 'calcium', 'edetate', 'valerate',
                                         'oleate', 'sucrose', 'iron', 'pyrophosphate', 'oxygen', 'sulfur', 'amphotericin', 'mesylate', 'tartrate',
                                         'maleate', 'lactobionate', 'propionate', 'arsenic', 'butyrate', 'fumarate', 'lutetium', 'yttrium', 'iodine',
                                         'cholesteryl sulfate', 'indium', 'palmitate', 'bran')
       AND cc.invalid_reason IS NULL
       AND c.concept_code NOT IN (SELECT hcpcs_code FROM definite_brand)
       ),

joined_ing AS
    (
    SELECT * FROM precise_to_ing
             UNION
    SELECT * FROM hcpcs_ing
    ),

-- join all HCPCS drug codes with ingredients:
ing_agg AS
    (SELECT hcpcs_code,
            hcpcs_name,
            array_agg(i.ing_id ORDER BY i.ing_id) AS ing_id,
            array_agg(i.ingredient ORDER BY i.ingredient) AS ingredient
    FROM joined_ing i
    WHERE i.ing_id NOT IN (SELECT j1.ing_id
                           FROM joined_ing j
                           JOIN joined_ing j1
                           ON j.hcpcs_code = j1.hcpcs_code
                           WHERE j.ingredient LIKE '%'||(j1.ingredient)||'%'
                           AND j.ing_id != j1.ing_id)
    GROUP BY hcpcs_code, hcpcs_name
    ),

-- extract RxN Brands AND its ingredients AND combinations:
cr_Brand AS
    (SELECT array_agg(cr.concept_id_1 ORDER BY concept_id_1) AS ing_id,
            array_agg(c1.concept_name ORDER BY c1.concept_name) AS ingredient,
            concept_id_2 AS brand_id,
            c.concept_name AS brand_name
    FROM concept_relationship cr
    JOIN concept c ON c.concept_id = cr.concept_id_2
    JOIN concept c1 ON c1.concept_id = cr.concept_id_1
    WHERE relationship_id IN ('Has brand name')
    AND c1. concept_class_id = 'Ingredient'
    AND c.vocabulary_id = 'RxNorm'
    AND cr.invalid_reason IS NULL
    GROUP BY concept_id_2, c.concept_name
    ),

-- join all HCPCS codes with brand names:
final_tab AS
    (SELECT DISTINCT hcpcs_code,
                     hcpcs_name,
                     'possible brand' AS flag,
                      CASE WHEN count(Brand_name) OVER (PARTITION BY hcpcs_code) > 1
                          THEN 'Multiple brands'
                      WHEN brand_name IS NULL
                          THEN 'No brand'
                      ELSE brand_name END
                          AS brand
    FROM ing_agg i
    LEFT JOIN cr_Brand b ON i.ing_id = b.ing_id

    UNION ALL

    SELECT * FROM definite_brand
    )

SELECT m.concept_code AS source_code,
       m.concept_name AS source_name,
       CASE WHEN hcpcs_name IS NOT NULL
           THEN u.flag
           ELSE 'no ing detected' -- e.g. there's a typo in the source
           END AS flag,
       brand,
       CASE WHEN m.mapped_brand = brand THEN 'correct mapping'
            ELSE 'review mapping'END AS mapping,
        target_name,
        target_vocab
FROM final_tab u
RIGHT JOIN mapped_brand m ON m.concept_code = u.hcpcs_code
ORDER BY mapping, flag, hcpcs_code
    ;



