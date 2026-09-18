#!/bin/bash
# Carga una base representativa (~150k filas) usando el motor SEQUENCE de MariaDB.
set -e
mariadb --protocol=socket -uroot -p"$MARIADB_ROOT_PASSWORD" "${APP_DB}" << 'SQL'
CREATE TABLE IF NOT EXISTS autores (
  id      INT AUTO_INCREMENT PRIMARY KEY,
  nombre  VARCHAR(120) NOT NULL,
  pais    VARCHAR(60),
  INDEX idx_nombre (nombre)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS libros (
  id        INT AUTO_INCREMENT PRIMARY KEY,
  isbn      VARCHAR(20) NOT NULL,
  titulo    VARCHAR(200) NOT NULL,
  autor_id  INT NOT NULL,
  anio      SMALLINT,
  stock     SMALLINT DEFAULT 1,
  UNIQUE KEY uk_isbn (isbn),
  INDEX idx_autor (autor_id),
  INDEX idx_titulo (titulo)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS socios (
  id      INT AUTO_INCREMENT PRIMARY KEY,
  nombre  VARCHAR(120) NOT NULL,
  email   VARCHAR(140),
  alta    DATE,
  INDEX idx_email (email)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS prestamos (
  id           BIGINT AUTO_INCREMENT PRIMARY KEY,
  libro_id     INT NOT NULL,
  socio_id     INT NOT NULL,
  fecha        DATETIME NOT NULL,
  devuelto     TINYINT(1) DEFAULT 0,
  INDEX idx_libro (libro_id),
  INDEX idx_socio (socio_id),
  INDEX idx_fecha (fecha)
) ENGINE=InnoDB;

-- 2.000 autores
INSERT INTO autores (nombre, pais)
SELECT CONCAT('Autor ', seq), ELT(1+ (seq % 5),'AR','ES','MX','CL','UY')
FROM seq_1_to_2000;

-- 50.000 libros
INSERT INTO libros (isbn, titulo, autor_id, anio, stock)
SELECT LPAD(seq, 13, '0'), CONCAT('Titulo numero ', seq),
       1 + (seq % 2000), 1950 + (seq % 75), 1 + (seq % 5)
FROM seq_1_to_50000;

-- 20.000 socios
INSERT INTO socios (nombre, email, alta)
SELECT CONCAT('Socio ', seq), CONCAT('socio', seq, '@uni.edu.ar'),
       DATE_SUB(CURDATE(), INTERVAL (seq % 2000) DAY)
FROM seq_1_to_20000;

-- 100.000 prestamos
INSERT INTO prestamos (libro_id, socio_id, fecha, devuelto)
SELECT 1 + (seq % 50000), 1 + (seq % 20000),
       NOW() - INTERVAL (seq % 500) DAY, seq % 2
FROM seq_1_to_100000;
SQL
echo ">> Datos cargados."
