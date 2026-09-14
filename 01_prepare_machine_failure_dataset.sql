-- Промежуточная аттестация Трофимов Дмитрий
-- Подготовка данных для анализа аварийных остановок оборудования.
--
-- Бизнес-задача:
-- хочу определить показатели оборудования, которые могут быть связаны
-- с аварийными остановками, чтобы в дальнейшем использовать их
-- для прогнозирования отказов.


-- ============================================================
-- 1. Смотрю какие типы событий оборудования есть в базе
-- ============================================================

SELECT
    event_type_id,
    event_code,
    event_name,
    event_category
FROM machine_event_types
ORDER BY event_type_id;


-- ============================================================
-- 2. Проверяю какие типы датчиков есть в базе
-- ============================================================

SELECT
    sensor_type_id,
    type_code,
    type_name,
    unit_of_measure,
    min_value,
    max_value
FROM sensor_types
ORDER BY sensor_type_id;


-- ============================================================
-- 3. Создаю представление с событиями оборудования
-- Аварийную остановку BREAKDOWN отмечаю отдельно.
-- Это будет целевая переменная для дальнейшего анализа.
-- ============================================================

CREATE OR REPLACE VIEW vw_machine_failure_analysis AS
SELECT
    me.machine_event_id,
    me.machine_id,
    m.machine_code,
    m.machine_name,
    m.machine_type_id,
    m.line_id,
    me.started_at,
    me.ended_at,
    me.severity,
    met.event_code,
    met.event_name,
    met.event_category,
    CASE
        WHEN met.event_code = 'BREAKDOWN' THEN 1
        ELSE 0
    END AS is_breakdown
FROM machine_events me
JOIN machines m
    ON me.machine_id = m.machine_id
JOIN machine_event_types met
    ON me.event_type_id = met.event_type_id;


-- ============================================================
-- 4. Проверяю количество аварийных и остальных событий
-- ============================================================

SELECT
    is_breakdown,
    COUNT(*) AS event_count
FROM vw_machine_failure_analysis
GROUP BY is_breakdown
ORDER BY is_breakdown;

-- В полученных данных:
-- 0 - 23349 обычных событий
-- 1 - 148 аварийных остановок
-- Всего - 23497 событий.


-- ============================================================
-- 5. Формирую итоговый датасет
--
-- Для каждого события беру последние известные показания
-- датчиков перед началом этого события.
--
-- В качестве признаков использую:
-- температуру, вибрацию, давление, обороты,
-- мощность и влажность.
--
-- is_breakdown:
-- 1 - аварийная остановка
-- 0 - другое событие
-- ============================================================

CREATE OR REPLACE VIEW vw_machine_failure_dataset AS
SELECT
    me.machine_event_id,
    me.machine_id,
    m.machine_code,
    m.machine_name,
    me.started_at,

    MAX(sr.numeric_value) FILTER (
        WHERE st.type_code = 'TEMPERATURE'
    ) AS temperature,

    MAX(sr.numeric_value) FILTER (
        WHERE st.type_code = 'VIBRATION'
    ) AS vibration,

    MAX(sr.numeric_value) FILTER (
        WHERE st.type_code = 'PRESSURE'
    ) AS pressure,

    MAX(sr.numeric_value) FILTER (
        WHERE st.type_code = 'RPM'
    ) AS rpm,

    MAX(sr.numeric_value) FILTER (
        WHERE st.type_code = 'POWER'
    ) AS power,

    MAX(sr.numeric_value) FILTER (
        WHERE st.type_code = 'HUMIDITY'
    ) AS humidity,

    CASE
        WHEN met.event_code = 'BREAKDOWN' THEN 1
        ELSE 0
    END AS is_breakdown

FROM machine_events me
JOIN machines m
    ON me.machine_id = m.machine_id
JOIN machine_event_types met
    ON me.event_type_id = met.event_type_id
LEFT JOIN sensors s
    ON m.machine_id = s.machine_id
LEFT JOIN sensor_types st
    ON s.sensor_type_id = st.sensor_type_id
LEFT JOIN LATERAL (
    SELECT
        sr1.numeric_value
    FROM sensor_readings sr1
    WHERE sr1.sensor_id = s.sensor_id
      AND sr1.recorded_at <= me.started_at
    ORDER BY sr1.recorded_at DESC
    LIMIT 1
) sr
    ON TRUE
GROUP BY
    me.machine_event_id,
    me.machine_id,
    m.machine_code,
    m.machine_name,
    me.started_at,
    met.event_code;


-- ============================================================
-- 6. Проверяю итоговый датасет
-- ============================================================

SELECT *
FROM vw_machine_failure_dataset
LIMIT 20;


-- ============================================================
-- 7. Проверяю количество строк
-- ============================================================

SELECT
    COUNT(*) AS total_rows
FROM vw_machine_failure_dataset;

-- Получено 23497 строк.


-- ============================================================
-- 8. Проверяю распределение целевой переменной
-- ============================================================

SELECT
    is_breakdown,
    COUNT(*) AS event_count,
    ROUND(
        100.0 * COUNT(*) /
        SUM(COUNT(*)) OVER (),
        2
    ) AS event_percent
FROM vw_machine_failure_dataset
GROUP BY is_breakdown
ORDER BY is_breakdown;


-- ============================================================
-- 9. Итоговая выборка для выгрузки в CSV
-- ============================================================

SELECT *
FROM vw_machine_failure_dataset;
