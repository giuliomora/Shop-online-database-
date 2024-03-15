############################################################################
################           Creazione DATABASE	           #################
############################################################################

drop database if exists PCSHOP; 
create database if not exists PCSHOP;
use PCSHOP;

############################################################################
################            Creazione tabelle              ################# 
############################################################################

drop table if exists Inserimento;
drop table if exists Effettuazione;
drop table if exists Fattura;
drop table if exists Ordine;
drop table if exists Carrello;
drop table if exists Giacenza;
drop table if exists Prodotto;
drop table if exists Cliente;

create table if not exists Cliente(
IDutente varchar(20) primary key,
nome varchar(20),
cognome varchar(20),
email varchar(50),
indirizzo varchar(50),
partitaIva varchar(11) default NULL,
telefono varchar(10)
) ENGINE=INNODB;

create table if not exists Prodotto(
IDProdotto varchar(7) primary key,
nome varchar(50),
categoria varchar(20),
anno year default NULL,
prezzo decimal(6,2)
) ENGINE=INNODB;

create table if not exists Giacenza(
barcode int not null AUTO_INCREMENT,
IDProdotto varchar(7),
primary key(barcode),
foreign key (IDProdotto) references Prodotto(IDProdotto) on delete no action
);

create table if not exists Carrello(
IDCarrello int not null AUTO_INCREMENT,
quantita int default 0,
primary key(idCarrello)
) ENGINE=INNODB;

create table if not exists Ordine(
numOrdine int not null AUTO_INCREMENT,
dataOrdine date,
speseSpedizione int,
stato varchar(20),
idCarrello int not null,
primary key(numOrdine),
foreign key (idCarrello) references Carrello(idCarrello) on delete no action
) ENGINE=INNODB;

create table if not exists Fattura(
IDFattura int not null AUTO_INCREMENT,
dataFattura date,
numOrdine int,
primary key(idFattura),
foreign key (numOrdine) references Ordine(numOrdine)
) ENGINE=INNODB;

create table if not exists Effettuazione(
numOrdine int not null,
IDutente varchar(20) not null,
primary key(numOrdine, IDutente),
foreign key (numOrdine) references Ordine(numOrdine) on delete no action,
foreign key (IDutente) references Cliente(IDutente) on delete no action
) ENGINE=INNODB;

create table if not exists Inserimento(
barcode int not null,
IDCarrello int not null,
primary key(barcode, IDCarrello),
foreign key (barcode) references Giacenza(barcode) on delete no action,
foreign key (IDCarrello) references Carrello(IDCarrello) on delete no action
) ENGINE=INNODB;

############################################################################
################        Operazioni a livello di schema     #################  
############################################################################

ALTER TABLE Prodotto
MODIFY prezzo decimal(7,2);

ALTER TABLE Carrello
ADD costoTotale decimal(7,2) default 0.0;

############################################################################
################                   Vista                   #################
############################################################################

DROP VIEW IF EXISTS ordini_in_corso;

create view ordini_in_corso as 
select ordine.numOrdine as numero_ordine,
		ordine.dataOrdine as data_ordine,
        carrello.quantita as quantita_ordinata,
        ordine.speseSpedizione as spese_spedizione,
        cliente.IDutente as username_cliente,
        cliente.indirizzo as indirizzo_cliente
from ordine
inner join carrello
	on ordine.IDCarrello = carrello.IDCarrello
inner join effettuazione
	on ordine.numOrdine = effettuazione.numOrdine
inner join cliente
	on effettuazione.IDutente = cliente.IDutente
where ordine.stato = 'in corso'
with local check option;

############################################################################
################                  Funzione                 ################# 
############################################################################

DROP FUNCTION IF EXISTS ordini_per_cliente;

DELIMITER $$
CREATE FUNCTION ordini_per_cliente(IDutente VARCHAR(20))
RETURNS INT
BEGIN
 DECLARE num INT default 0;
	SELECT count(*) INTO num
	FROM ordine
	INNER JOIN effettuazione
		ON ordine.numOrdine = effettuazione.numOrdine
	INNER JOIN cliente
		ON effettuazione.IDutente = cliente.IDutente
	WHERE cliente.IDutente = IDutente;
 RETURN num;
END $$
DELIMITER ;

############################################################################
################                  Procedura                #################
############################################################################

DROP PROCEDURE IF EXISTS calcola_costototale;

DELIMITER $$
CREATE PROCEDURE calcola_costototale(idCarr INT)
BEGIN
 DECLARE n decimal(6,2) default 0.00;
 IF (IDCarr IN (SELECT IDCarrello FROM Carrello WHERE Carrello.IDCarrello=IDCarr))
 THEN
	SELECT SUM(Prodotto.prezzo) INTO n
	FROM Carrello
	INNER JOIN Inserimento
		ON Carrello.IDCarrello = Inserimento.IDCarrello
	INNER JOIN Giacenza
		ON Inserimento.barcode = Giacenza.barcode
	INNER JOIN Prodotto
		ON Giacenza.IDProdotto = Prodotto.IDProdotto
	WHERE Carrello.IDCarrello = IDCarr;
 END IF;
 
 IF(n > 0.00)
 THEN
	 UPDATE Carrello SET costoTotale=n WHERE IDCarrello = IDCarr;
 END IF;
END $$
DELIMITER ;

DROP PROCEDURE IF EXISTS p_togli_iva;
DELIMITER $$
CREATE PROCEDURE p_togli_iva(numOrdine INT)
BEGIN
DECLARE piva varchar(11) default null;
	IF (numOrdine IN (SELECT numOrdine FROM effettuazione WHERE effettuazione.numOrdine=numOrdine))
    THEN
		SELECT partitaIVA into piva
        FROM effettuazione NATURAL JOIN cliente NATURAL JOIN ordine NATURAL JOIN carrello
        where effettuazione.numOrdine=numOrdine;
    END IF;
    
	IF(piva is not null)
    THEN
		UPDATE Carrello SET costoTotale=costoTotale*78/100;
	END IF;
END $$
DELIMITER ;

############################################################################
################                    Trigger                ################# 
############################################################################

DROP TRIGGER IF EXISTS calcola_quantita;
DELIMITER $$
CREATE TRIGGER calcola_quantita
AFTER INSERT ON Inserimento
FOR EACH ROW
BEGIN
	DECLARE n INT;
    SELECT COUNT(*) INTO n FROM Inserimento WHERE Inserimento.IDCarrello=NEW.IDCarrello;
	IF (n > 0)
		THEN UPDATE Carrello SET quantita=n WHERE IDCarrello=NEW.IDCarrello;
	END IF;
END $$
DELIMITER ;

DROP TRIGGER IF EXISTS inserimento_carrello;
DELIMITER $$
CREATE TRIGGER inserimento_carrello
AFTER INSERT ON inserimento
FOR EACH ROW
BEGIN
	CALL calcola_costototale(NEW.IDCarrello);
END $$
DELIMITER ;

DROP TRIGGER IF EXISTS togli_iva;
DELIMITER $$
CREATE TRIGGER togli_iva
AFTER INSERT ON effettuazione
for each row
BEGIN
	CALL p_togli_iva(NEW.numOrdine);
END $$
DELIMITER ;

############################################################################
################            Popolamento database           #################
############################################################################

SET GLOBAL local_infile=1;

load data local infile 'prodotti.csv'   #inserire filepath
into table Prodotto
fields terminated by ','
lines terminated by '\n'
ignore 1 rows;

load data local infile 'clienti.txt'    #inserire filepath
into table Cliente
fields terminated by ';'
optionally enclosed by'"'
lines terminated by '\n'
ignore 1 rows;

INSERT INTO Giacenza (barcode, IDProdotto) VALUES 
(1523000, 4986127),
(1523001, 4986127),
(1523002, 4986127),
(1523003, 4986127),
(1523004, 4986127),
(1523005, 4986127),
(1523006, 7943045),
(1523007, 7943045),
(1523008, 7943045),
(1523009, 7943045),
(1523010, 7943045),
(1523011, 7943045),
(1523012, 9634561),
(1523013, 9634561),
(1523014, 9634561),
(1523015, 7963142),
(1523016, 7963142),
(1523017, 7963142),
(1523018, 7963142),
(1523019, 7885641),
(1523020, 7885641),
(1523021, 7885641),
(1523022, 7885641),
(1523023, 7885641),
(1523024, 7885641),
(1523025, 1278934),
(1523026, 1278934),
(1523027, 1278934),
(1523028, 1278934),
(1523029, 1278934),
(1523030, 1278934),
(1523031, 7653012),
(1523032, 7653012),
(1523033, 9486321),
(1523034, 9486321),
(1523035, 9486321),
(1523036, 9012345),
(1523037, 9012345),
(1523038, 9012345),
(1523039, 9012345),
(1523040, 1193403),
(1523041, 1193403),
(1523042, 8893210),
(1523043, 1193403),
(1523044, 8893210),
(1523045, 5644055),
(1523046, 5644055),
(1523047, 7653201),
(1523048, 7653201),
(1523049, 7653201),
(1523050, 7653201),
(1523051, 7653201),
(1523052, 7653201),
(1523053, 7653201),
(1523054, 9870040),
(1523055, 9870040),
(1523056, 9870040),
(1523057, 9870040),
(1523058, 9870040),
(1523059, 8870000),
(1523060, 8870000),
(1523061, 8870000),
(1523090, 8870000);

INSERT INTO Carrello (IDCarrello, quantita) VALUES
(4167001,0),
(4167002,0),
(4167003,0),
(4167004,0),
(4167005,0),
(4167006,0),
(4167007,0);

INSERT INTO Inserimento (barcode, IDCarrello) VALUES
(1523000,4167001),
(1523009,4167001),
(1523029,4167002),
(1523033,4167002),
(1523002,4167002),
(1523016,4167003),
(1523011,4167005),
(1523012,4167005),
(1523041,4167004),
(1523042,4167004),
(1523013,4167005),
(1523037,4167006),
(1523058,4167004);

INSERT INTO Ordine (numOrdine, dataOrdine, speseSpedizione, stato, IDCarrello) VALUES 
(1,'2020-01-23',5,'concluso',4167001),
(2,'2020-03-16',18,'concluso',4167002),
(3,'2020-07-21',25,'concluso',4167003),
(4,'2020-12-11',5,'in corso',4167004),
(5,'2020-01-18',10,'concluso',4167005),
(6,'2021-01-24',8,'in corso',4167006);

INSERT INTO Fattura (IDFattura, dataFattura, numOrdine) VALUES 
(1,'2020-01-23',1),
(2,'2020-03-26',2),
(3,'2020-07-24',3),
(4,'2021-01-18',5);

INSERT INTO Effettuazione (numOrdine, IDutente) VALUES 
(1,'Bacaruso'),
(2,'joco'),
(3,'Fabe'),
(4,'bigG'),
(5,'Pojak'),
(6,'Pojak');

############################################################################
################                    Query                  #################
############################################################################

-- 1. Trovare i clienti che hanno un ID utente più lungo di 3 caratteri e  termina con 'a'.
select * from cliente where length(IDutente)>3 and IDutente like '%a'; 

-- 2. Trovare i prodotti di categoria 'Streaming' disponibili nel magazzino.
select barcode, nome from Prodotto natural join Giacenza where categoria='Streaming';  

-- 3. Trovare nome, cognome, dataOrdine dei clienti che a Gennaio 2020 hanno effettuato un ordine
-- e non hanno la partitaIva.
select nome, cognome, dataOrdine
from cliente natural join effettuazione natural join ordine
where partitaIva is null
and month(dataOrdine)='01' and year(dataOrdine)='2020';
