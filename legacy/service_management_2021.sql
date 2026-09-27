--
-- Database: service_management
--
CREATE DATABASE IF NOT EXISTS service_management ;
USE service_management;

-- --------------------------------------------------------

CREATE TABLE customer (
  Customer_ID char(15) PRIMARY KEY,
  Customer_Name varchar (20) NOT NULL,
  Telephone_Number char(13)
);

INSERT INTO customer(Customer_ID, Customer_Name, Telephone_Number) VALUES
('C-01', 'Nanine Coenraets', '(699) 3284252'),
('C-02', 'Shantee Glynne', '(763) 3162634'),
('C-03', 'Nevin Cudbird', '(664) 5402420'),
('C-04', 'Ceciley Lanceley', '(160) 2435327'),
('C-05', 'Rollie Roskams', '(506) 1493502'),
('C-06', 'Currie Bugbee', null),
('C-07', 'Colly Devitt', '(125) 6761053'),
('C-08', 'Zachariah Vankeev', '(944) 7952010'),
('C-09', 'Gustie Imbrey', '(739) 1650288'),
('C-10', 'Annemarie Hearons', '(916) 7929168'),
('C-11', 'Hedvig Mathison', '(389) 6684803'),
('C-12', 'Eduardo Spaducci', '(400) 6040298'),
('C-13', 'Crawford Thorold', '(952) 4442341'),
('C-14', 'Gertrudis Buckner', '(892) 4766599'),
('C-15', 'Humfrey O''Hickey', '(794) 7628848'),
('C-16', 'Jourdan Wescott', '(697) 4159094'),
('C-17', 'Ruth Domanek', '(993) 7283035'),
('C-18', 'Julissa Klimentov', '(115) 2144328'),
('C-19', 'Solly Rousell', '(902) 4708587'),
('C-20', 'Bendicty Neesham', '(603) 6039443'),
('C-21', 'Broddie Westman', '(678) 3713279'),
('C-22', 'Rodolphe Lashbrook', '(270) 1243189'),
('C-23', 'Reggis Glanvill', '(918) 7516640'),
('C-24', 'Zarla Phebey', '(172) 9696078'),
('C-25', 'Kizzie Wooddisse', '(578) 8599274'),
('C-26', 'Cahra Avrahamov', '(840) 4519950'),
('C-27', 'Bogart Northeast', '(844) 7118974'),
('C-28', 'Derry Pinnijar', '(367) 3793505'),
('C-29', 'Ashleigh Wortt', '(388) 5051959'),
('C-30', 'Roby Pavlenkov', '(517) 6680585'),
('C-31', 'Gaby Aim', '(512) 1158937'),
('C-32', 'Britte Grout', '(327) 6112310'),
('C-33', 'Patricio Dispencer', '(548) 1354186'),
('C-34', 'Lulu McPhilemy', '(945) 3625899'),
('C-35', 'June Roxbrough', '(988) 3724252'),
('C-36', 'Robena Gerlts', '(263) 4537200'),
('C-37', 'Randy Wykes', '(832) 2475524'),
('C-38', 'Cariotta Fleeming', '(911) 4105619'),
('C-39', 'Berke Skurm', '(770) 6615595'),
('C-40', 'Arney Grzesiewicz', '(299) 6350412'),
('C-41', 'Leicester Alvin', '(479) 5852377'),
('C-42', 'Vidovik Casone', '(300) 8812537'),
('C-43', 'Devinne Gowler', null),
('C-44', 'Katrinka Kenway', '(856) 3769725'),
('C-45', 'Conny Giacomuzzo', '(763) 8342338'),
('C-46', 'Early Tidbold', '(661) 3181209'),
('C-47', 'Rogerio Batha', '(594) 6499436'),
('C-48', 'Orly Creeber', '(279) 2273969'),
('C-49', 'Lawry Goodbody', '(587) 8400596'),
('C-50', 'Tobias Marryatt', '(913) 4533087');

/* ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- */

CREATE TABLE appointment(
	Appt_Number char(10) PRIMARY KEY,
    Customer_ID char(15),
    Appt_Date date NOT NULL,
    Appt_Time varchar(20) NOT NULL,
    FOREIGN KEY (customer_id) REFERENCES customer(Customer_ID)
);

INSERT INTO appointment (Appt_Number, Customer_ID, Appt_Date, Appt_Time) VALUES 
('A-01', 'C-01', '2021/06/15', '12:21 PM'),
('A-02', 'C-02', '2021/04/28', '10:57 AM'),
('A-03', 'C-03', '2021/06/30', '3:28 PM'),
('A-04', 'C-04', '2021/02/13', '2:03 PM'),
('A-05', 'C-05', '2021/02/22', '11:03 AM'),
('A-06', 'C-06', '2021/09/15', '3:21 PM'),
('A-07', 'C-07', '2021/02/26', '10:44 AM'),
('A-08', 'C-08', '2021/06/11', '12:30 PM'),
('A-09', 'C-09', '2021/11/07', '2:14 PM'),
('A-10', 'C-10', '2021/10/12', '12:57 PM'),
('A-11', 'C-11', '2021/10/16', '4:42 PM'),
('A-12', 'C-12', '2021/10/06', '1:30 PM'),
('A-13', 'C-13', '2021/11/28', '1:28 PM'),
('A-14', 'C-14', '2021/10/03', '1:32 PM'),
('A-15', 'C-15', '2021/04/13', '3:13 PM'),
('A-16', 'C-16', '2021/01/25', '10:12 AM'),
('A-17', 'C-17', '2021/02/24', '4:33 PM'),
('A-18', 'C-18', '2021/04/24', '2:27 PM'),
('A-19', 'C-19', '2021/05/12', '2:22 PM'),
('A-20', 'C-20', '2021/08/18', '4:21 PM'),
('A-21', 'C-21', '2021/04/24', '1:59 PM'),
('A-22', 'C-22', '2021/01/25', '4:42 PM'),
('A-23', 'C-23', '2021/09/02', '12:05 PM'),
('A-24', 'C-24', '2021/07/17', '11:11 AM'),
('A-25', 'C-25', '2021/10/18', '11:30 AM'),
('A-26', 'C-26', '2021/10/04', '10:12 AM'),
('A-27', 'C-27', '2021/11/20', '12:56 PM'),
('A-28', 'C-28', '2021/07/23', '12:38 PM'),
('A-29', 'C-29', '2021/11/25', '12:09 PM'),
('A-30', 'C-30', '2021/09/18', '1:14 PM'),
('A-31', 'C-31', '2021/10/23', '5:06 PM'),
('A-32', 'C-32', '2021/06/06', '2:29 PM'),
('A-33', 'C-33', '2021/10/06', '4:22 PM'),
('A-34', 'C-34', '2021/03/17', '5:29 PM'),
('A-35', 'C-35', '2021/08/23', '2:42 PM'),
('A-36', 'C-36', '2021/11/12', '4:28 PM'),
('A-37', 'C-37', '2021/01/16', '9:30 AM'),
('A-38', 'C-38', '2021/10/24', '10:39 AM'),
('A-39', 'C-39', '2021/05/06', '5:24 PM'),
('A-40', 'C-40', '2021/03/12', '4:35 PM'),
('A-41', 'C-41', '2021/08/01', '10:23 AM'),
('A-42', 'C-42 ', '2021/03/26', '11:06 AM'),
('A-43', 'C-43', '2021/04/24', '3:21 PM'),
('A-44', 'C-44', '2021/04/09', '9:55 AM'),
('A-45', 'C-45', '2021/01/10', '1:29 PM'),
('A-46', 'C-46', '2021/11/05', '1:49 PM'),
('A-47', 'C-47', '2021/03/02', '12:36 PM'),
('A-48', 'C-48', '2021/11/09', '2:15 PM'),
('A-49', 'C-49', '2021/03/16', '3:14 PM'),
('A-50', 'C-50', '2021/08/22', '11:59 AM');

/* ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- */

CREATE TABLE Vehicle(
	VIN char(17) PRIMARY KEY,
    Customer_ID char(15),
    Make varchar(20) NOT NULL,
    Model varchar(20) NOT NULL,
    Year char(5),
    FOREIGN KEY (customer_id) REFERENCES customer(Customer_ID)
);

INSERT INTO VEHICLE (VIN, Customer_ID, Make, Model, Year) VALUES
('WAUVC68E42A107501', 'C-01', 'Mercedes-Benz', 'SLR McLaren', 2008),
('1GYS4CEF6BR511619', 'C-02', 'Mercedes-Benz', 'C-Class', 1997),
('1G6DC5EY0B0788692', 'C-03', 'BMW', '750', 2006),
('3D7LP2ET1AG409537', 'C-04', 'Buick', 'Roadmaster', 1995),
('1FTSW2B51AE060852', 'C-05', 'Infiniti', 'QX56', 2007),
('WAUGL68E95A637492', 'C-06', 'BMW', 'M5', 2000),
('3D73M4EL7AG269742', 'C-07', 'Pontiac', 'Bonneville', 1995),
('1N6AD0CU0CN046195', 'C-08', 'Lincoln', 'Blackwood', 2003),
('JN1CV6EK5BM624676', 'C-09', 'Oldsmobile', '98', 1992),
('WBAGL63584D028463', 'C-10', 'Dodge', 'Ram 3500 Club', 1996),
('5GADV23L36D759491', 'C-11', 'Ford', 'Escort', 1990),
('JM1BL1H43A1257081', 'C-12', 'Hyundai', 'Elantra', 2013),
('SCFFDCCD1AG171400', 'C-13', 'Jeep', 'Wrangler', 2006),
('WP0AA2A96ES584006', 'C-14', 'Chevrolet', 'Camaro', 1975),
('KMHHT6KD3EU102529', 'C-15', 'Subaru', 'Tribeca', 2010),
('WBABS53471E812234', 'C-16', 'Mercury', 'Lynx', 1987),
('5NPDH4AE7CH330687', 'C-17', 'Toyota', 'Corolla', 1995),
('3VWKX7AJ1AM661259', 'C-18', 'Suzuki', 'X-90', 1998),
('1FAHP2DW0AG257716', 'C-19', 'Mazda', 'Navajo', 1991),
('2C3CDXBG2EH966569', 'C-20', 'Toyota', 'Camry', 2001),
('1G6AB5SAXE0703763', 'C-21', 'Acura', 'CL', 2001),
('3FA6P0SU3FR598685', 'C-22', 'Audi', 'A8', 2011),
('2T1BURHE9EC507932', 'C-23', 'Chevrolet', 'Silverado 3500', 2007),
('1GYS3PKJ2FR233584', 'C-24', 'Toyota', 'T100', 1998),
('1G6AK5S31D0247846', 'C-25', 'Nissan', 'Maxima', 1993),
('1N6AF0KY5EN169914', 'C-26', 'Mitsubishi', 'GTO', 1993),
('5J6TF2H59EL253132', 'C-27', 'Saab', '9-3', 2007),
('WDDGF5EB1AA785926', 'C-28', 'Hyundai', 'Elantra', 1998),
('VNKKTUD39FA642450', 'C-29', 'Audi', 'TT', 2001),
('1GYS3BEF4CR652106', 'C-30', 'Chevrolet', 'Suburban 2500', 1995),
('4T1BD1FK3DU703999', 'C-31', 'Ford', 'Explorer', 2003),
('2G61L5S31F9133450', 'C-32', 'Oldsmobile', '88', 1999),
('SALFP2BN3BH556844', 'C-33', 'Chrysler', '300M', 2000),
('1GYUCHEF2AR127960', 'C-34', 'Chevrolet', '1500', 1996),
('WBSPM9C54AE332793', 'C-35', 'Toyota', 'Solara', 2004),
('WBAVB73568V221887', 'C-36', 'Oldsmobile', 'Silhouette', 1999),
('WDDGF5EB0AF166768', 'C-37', 'Audi', 'TT', 2001),
('WVGFF9BP8BD152008', 'C-38', 'Kia', 'Rio', 2003),
('WBA3V7C58FP073712', 'C-39', 'Chevrolet', 'Monte Carlo', 1998),
('WAUEFAFL0FN178933', 'C-40', 'Pontiac', 'Grand Prix', 1994),
('WAUVC58E63A098666', 'C-41', 'Ford', 'Bronco II', 1986),
('JTHFF2C24D2799002', 'C-42', 'Mazda', '626', 1994),
('1GYS3DEF1ER988116', 'C-43', 'Mercury', 'Mystique', 1999),
('WAUCFAFR3EA282799', 'C-44', 'Mitsubishi', 'Galant', 1984),
('5FRYD4H60FB092372', 'C-45', 'Honda', 'Accord Crosstour', 2010),
('JH4CU4F41BC696693', 'C-46', 'Isuzu', 'Trooper', 2000),
('1C4RDJAG1EC717428', 'C-47', 'Acura', 'Integra', 2000),
('2D4RN4DG0BR493424', 'C-48', 'BMW', 'X5', 2008),
('1C4RDJEG7DC388632', 'C-49', 'Mazda', 'Mazda3', 2009),
('1G6KE57Y93U706080', 'C-50', 'Ford', 'Crown Victoria', 1997);

/* ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- */

CREATE TABLE bill(
	Bill_Number varchar(20) PRIMARY KEY NOT NULL,
    Customer_ID char(15),
    Payment_Date date NOT NULL,
    Payment_Type varchar(15) NOT NULL,
    Total_Bill decimal(7,2) NOT NULL,
    FOREIGN KEY (customer_id) REFERENCES customer(Customer_ID)
);


INSERT INTO bill (Bill_Number, Customer_ID, Payment_Date, Payment_Type, Total_Bill) VALUES
('B-0001', 'C-01', '2021/06/15', 'visa', 313.72),
('B-0002', 'C-02', '2021/04/28', 'mastercard', 3997.54),
('B-0003', 'C-03', '2021/06/30', 'visa', 1066.69),
('B-0004', 'C-04', '2021/02/13', 'bankcard', 3639.37),
('B-0005', 'C-05', '2021/02/22', 'visa', 927.42),
('B-0006', 'C-06', '2021/09/15', 'mastercard', 336.69),
('B-0007', 'C-07', '2021/02/26', 'americanexpress', 193.06),
('B-0008', 'C-08', '2021/06/11', 'bankcard', 3179.74),
('B-0009', 'C-09', '2021/11/07', 'americanexpress', 594.82),
('B-0010', 'C-10', '2021/10/12', 'bankcard', 3003.75),
('B-0011', 'C-11', '2021/10/16', 'mastercard', 1444.12),
('B-0012', 'C-12', '2021/10/06', 'jcb', 735.85),
('B-0013', 'C-13', '2021/11/28', 'visa', 335.52),
('B-0014', 'C-14', '2021/10/03', 'bankcard', 39.19),
('B-0015', 'C-15', '2021/04/13', 'mastercard', 359.54),
('B-0016', 'C-16', '2021/01/25', 'jcb', 1008.27),
('B-0017', 'C-17', '2021/02/24', 'jcb', 522.00),
('B-0018', 'C-18', '2021/04/24', 'visa', 728.32),
('B-0019', 'C-19', '2021/05/12', 'americanexpress', 3815.31),
('B-0020', 'C-20', '2021/08/18', 'americanexpress', 132.33),
('B-0021', 'C-21', '2021/04/24', 'bankcard', 1142.34),
('B-0022', 'C-22', '2021/01/25', 'jcb', 1389.89),
('B-0023', 'C-23', '2021/09/02', 'bankcard', 599.68),
('B-0024', 'C-24', '2021/07/17', 'jcb', 222.92),
('B-0025', 'C-25', '2021/10/18', 'mastercard', 2589.28),
('B-0026', 'C-26', '2021/10/04', 'mastercard', 2371.48),
('B-0027', 'C-27', '2021/11/20', 'jcb', 40.41),
('B-0028', 'C-28', '2021/07/23', 'jcb', 382.81),
('B-0029', 'C-29', '2021/11/25', 'americanexpress', 350.85),
('B-0030', 'C-30', '2021/09/18', 'americanexpress', 838.94),
('B-0031', 'C-31', '2021/10/23', 'americanexpress', 2853.30),
('B-0032', 'C-32', '2021/06/06', 'bankcard', 3772.38),
('B-0033', 'C-33', '2021/10/06', 'mastercard', 64.27),
('B-0034', 'C-34', '2021/03/17', 'bankcard', 3756.34),
('B-0035', 'C-35', '2021/08/23', 'mastercard', 738.97),
('B-0036', 'C-36', '2021/11/12', 'bankcard', 130.31),
('B-0037', 'C-37', '2021/01/16', 'americanexpress', 3091.99),
('B-0038', 'C-38', '2021/10/24', 'visa', 954.88),
('B-0039', 'C-39', '2021/05/06', 'americanexpress', 2192.68),
('B-0040', 'C-40', '2021/03/12', 'americanexpress', 368.53),
('B-0041', 'C-41', '2021/08/01', 'visa', 99.67),
('B-0042', 'C-42', '2021/03/26', 'visa', 3210.61),
('B-0043', 'C-43', '2021/04/24', 'bankcard', 921.60),
('B-0044', 'C-44', '2021/04/09', 'americanexpress', 961.11),
('B-0045', 'C-45', '2021/01/10', 'jcb', 1996.38),
('B-0046', 'C-46', '2021/11/05', 'americanexpress', 659.93),
('B-0047', 'C-47', '2021/03/02', 'mastercard', 78.74),
('B-0048', 'C-48', '2021/11/09', 'jcb', 352.64),
('B-0049', 'C-49', '2021/03/16', 'visa', 1056.83),
('B-0050', 'C-50', '2021/08/22', 'bankcard', 210.22);

/* ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- */

CREATE TABLE service(
	Service_ID varchar(15) PRIMARY KEY,
    Start_Date date NOT NULL,
    Finish_Date date,
    Service_Status varchar (15) NOT NULL DEFAULT 'incomeplete'
);

INSERT INTO service (Service_ID, Start_Date, Finish_Date, Service_Status) VALUES 
('S-01','2021/06/15', null ,'Incomeplete'),  
('S-02','2021/04/28','2021/04/28','Complete'),
('S-03','2021/06/30','2021/06/30','Complete'),
('S-04','2021/02/13','2021/02/15','Complete'),
('S-05','2021/02/22', null ,'Incomeplete'),
('S-06','2021/09/15', null ,'Incomeplete'),
('S-07','2021/02/26','2021/02/28','Complete'),
('S-08','2021/06/11', null ,'Incomeplete'),
('S-09','2021/11/07','2021/11/18','Complete'),
('S-10','2021/10/12', null ,'Incomeplete'),
('S-11','2021/10/16','2021/10/18','Complete'),
('S-12','2021/10/06', null ,'Incomeplete'),
('S-13','2021/11/28', null ,'Incomeplete'),
('S-14','2021/10/03','2021/10/10','Complete'),
('S-15','2021/04/13','2021/04/30','Complete'),
('S-16','2021/01/25', null ,'Incomeplete'),
('S-17','2021/02/24','2021/02/25','Complete'),
('S-18','2021/04/24','2021/04/29','Complete'),
('S-19','2021/05/12','2021/05/13','Complete'),
('S-20','2021/08/18', null ,'Incomeplete'),
('S-21','2021/04/24','2021/04/30','Complete'),
('S-22','2021/01/25','2021/01/28','Complete'),
('S-23','2021/09/02','2021/09/03','Complete'),
('S-24','2021/07/17', null ,'Incomeplete'),
('S-25','2021/10/18','2021/10/22','Complete'),
('S-26','2021/10/04','2021/10/09','Complete'),
('S-27','2021/11/20', null ,'Incomeplete'),
('S-28','2021/07/23', null ,'Incomeplete'),
('S-29','2021/11/25','2021/11/29','Complete'),
('S-30','2021/09/18', null ,'Incomeplete'),
('S-31','2021/10/23','2021/10/24','Complete'),
('S-32','2021/06/06','2021/06/23','Complete'),
('S-33','2021/08/06','2021/08/12','Complete'),
('S-34','2021/03/17', null ,'Incomeplete'),
('S-35','2021/11/23','2021/11/24','Complete'),
('S-36','2021/11/12','2021/11/16','Complete'),
('S-37','2021/03/16','2021/03/18','Complete'),
('S-38','2021/10/24','2021/10/29','Complete'),
('S-39','2021/05/06','2021/05/07','Complete'),
('S-40','2021/03/12', null ,'Incomeplete'),
('S-41','2021/08/01', null ,'Incomeplete'),
('S-42','2021/03/26','2021/03/29','Complete'),
('S-43','2021/04/24', null ,'Incomeplete'),
('S-44','2021/04/09','2021/04/17','Complete'),
('S-45','2021/01/10','2021/01/12','Complete'),
('S-46','2021/11/05','2021/11/28','Complete'),
('S-47','2021/03/02', null ,'Incomeplete'),
('S-48','2021/11/09','2021/11/15','Complete'),
('S-49','2021/03/16','2021/03/25','Complete'),
('S-50','2021/08/22', null ,'Incomeplete');

/* ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- */

CREATE TABLE service_cost(
	Service_ID varchar(15),
    Bill_Number varchar(20),
    FOREIGN KEY (service_id) REFERENCES service(service_id),
    FOREIGN KEY (bill_number) REFERENCES bill(bill_number)
);

INSERT INTO service_cost(Service_ID, Bill_Number) VALUES 
('S-01','B-0001'),
('S-02','B-0002'),
('S-03','B-0003'),
('S-04','B-0004'),
('S-05','B-0005'),
('S-06','B-0006'),
('S-07','B-0007'),
('S-08','B-0008'),
('S-09','B-0009'),
('S-10','B-0010'),
('S-11','B-0011'),
('S-12','B-0012'),
('S-13','B-0013'),
('S-14','B-0014'),
('S-15','B-0015'),
('S-16','B-0016'),
('S-17','B-0017'),
('S-18','B-0018'),
('S-19','B-0019'),
('S-20','B-0020'),
('S-21','B-0021'),
('S-22','B-0022'),
('S-23','B-0023'),
('S-24','B-0024'),
('S-25','B-0025'),
('S-26','B-0026'),
('S-27','B-0027'),
('S-28','B-0028'),
('S-29','B-0029'),
('S-30','B-0030'),
('S-31','B-0031'),
('S-32','B-0032'),
('S-33','B-0033'),
('S-34','B-0034'),
('S-35','B-0035'),
('S-36','B-0036'),
('S-37','B-0037'),
('S-38','B-0038'),
('S-39','B-0039'),
('S-40','B-0040'),
('S-41','B-0041'),
('S-42','B-0042'),
('S-43','B-0043'),
('S-44','B-0044'),
('S-45','B-0045'),
('S-46','B-0046'),
('S-47','B-0047'),
('S-48','B-0048'),
('S-49','B-0049'),
('S-50','B-0050');

/* ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- */

CREATE TABLE vehicle_receives(
	VIN char(17),
    Service_ID varchar(15),
    FOREIGN KEY (vin) REFERENCES vehicle(vin),
    FOREIGN KEY (service_id) REFERENCES service(service_ID)
);

INSERT INTO  vehicle_receives(VIN, Service_ID)VALUES
('WAUVC68E42A107501','S-01'),		
('1GYS4CEF6BR511619','S-02'),		
('1G6DC5EY0B0788692','S-03'),		
('3D7LP2ET1AG409537','S-04'),		
('1FTSW2B51AE060852','S-05'),		
('WAUGL68E95A637492','S-06'),		
('3D73M4EL7AG269742','S-07'),		
('1N6AD0CU0CN046195','S-08'),		
('JN1CV6EK5BM624676','S-09'),		
('WBAGL63584D028463','S-10'),		
('5GADV23L36D759491','S-11'),		
('JM1BL1H43A1257081','S-12'),		
('SCFFDCCD1AG171400','S-13'),		
('WP0AA2A96ES584006','S-14'),		
('KMHHT6KD3EU102529','S-15'),		
('WBABS53471E812234','S-16'),		
('5NPDH4AE7CH330687','S-17'),		
('3VWKX7AJ1AM661259','S-18'),		
('1FAHP2DW0AG257716','S-19'),		
('2C3CDXBG2EH966569','S-20'),		
('1G6AB5SAXE0703763','S-21'),		
('3FA6P0SU3FR598685','S-22'),		
('2T1BURHE9EC507932','S-23'),		
('1GYS3PKJ2FR233584','S-24'),		
('1G6AK5S31D0247846','S-25'),		
('1N6AF0KY5EN169914','S-26'),		
('5J6TF2H59EL253132','S-27'),		
('WDDGF5EB1AA785926','S-28'),		
('VNKKTUD39FA642450','S-29'),		
('1GYS3BEF4CR652106','S-30'),		
('4T1BD1FK3DU703999','S-31'),		
('2G61L5S31F9133450','S-32'),		
('SALFP2BN3BH556844','S-33'),		
('1GYUCHEF2AR127960','S-34'),		
('WBSPM9C54AE332793','S-35'),		
('WBAVB73568V221887','S-36'),		
('WDDGF5EB0AF166768','S-37'),		
('WVGFF9BP8BD152008','S-38'),		
('WBA3V7C58FP073712','S-39'),		
('WAUEFAFL0FN178933','S-40'),		
('WAUVC58E63A098666','S-41'),		
('JTHFF2C24D2799002','S-42'),		
('1GYS3DEF1ER988116','S-43'),		
('WAUCFAFR3EA282799','S-44'),		
('5FRYD4H60FB092372','S-45'),		
('JH4CU4F41BC696693','S-46'),		
('1C4RDJAG1EC717428','S-47'),		
('2D4RN4DG0BR493424','S-48'),		
('1C4RDJEG7DC388632','S-49'),		
('1G6KE57Y93U706080','S-50');		

/* ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- */

CREATE TABLE mechanic (
	Customer_ID char(15),
	Mechanic_ID varchar(15) PRIMARY KEY,
	Mechanic_Name varchar(20) NOT NULL,
    Phone_Number char(13) NOT NULL,
    FOREIGN KEY (customer_id) REFERENCES customer(Customer_ID)
);

INSERT INTO mechanic  (Customer_ID, Mechanic_ID, Mechanic_Name, Phone_Number) VALUES
('C-01', 'M-001', 'Iosep Titchmarsh', '(191) 6330240'),   
('C-02', 'M-002', 'Ivie Goodrich', '(501) 8640713'),
('C-03', 'M-003', 'Marley Gabey', '(184) 8469584'),
('C-04', 'M-004', 'Sarge Blowin', '(108) 5019874'),
('C-05', 'M-005', 'Ginnie Paradin', '(605) 2159905'),
('C-06', 'M-006', 'Krystalle Shale', '(314) 4622514'),
('C-07', 'M-007', 'Neil Redsell', '(103) 6067554'),
('C-08', 'M-008', 'Cybil Ferrier', '(678) 1152259'),
('C-09', 'M-009', 'Jo-ann Swinyard', '(390) 8086496'),
('C-10', 'M-010', 'Tibold Knotton', '(687) 6704021'),
('C-11', 'M-011', 'Josy Haslam', '(215) 1145018'),
('C-12', 'M-012', 'Edwin Gerrad', '(354) 3049683'),
('C-13', 'M-013', 'Alameda Benoix', '(707) 7842215'),
('C-14', 'M-014', 'Beckie Rains', '(132) 9314106'),
('C-15', 'M-015', 'Lizabeth Pickton', '(862) 8780383'),
('C-16', 'M-016', 'Wood Haliday', '(868) 5315837'),
('C-17', 'M-017', 'Rosaline Simka', '(533) 4717422'),
('C-18', 'M-018', 'Staci McGrae', '(530) 8142947'),
('C-19', 'M-019', 'Meghann Gaize', '(696) 6098340'),
('C-20', 'M-020', 'Larry Gridley', '(437) 7837064'),
('C-21', 'M-021', 'Wendy Lively', '(227) 8600153'),
('C-22', 'M-022', 'Cody Kmicicki', '(729) 9005474'),
('C-23', 'M-023', 'Willi Hadkins', '(824) 7439455'),
('C-24', 'M-024', 'Ottilie Aldrich', '(366) 5382836'),
('C-25', 'M-025', 'Belinda Virr', '(705) 6835795'),
('C-26', 'M-026', 'Shannon Craker', '(961) 6565237'),
('C-27', 'M-027', 'Kandace Ord', '(986) 9196335'),
('C-28', 'M-028', 'Gibb Couchman', '(311) 7002018'),
('C-29', 'M-029', 'Hastings Bolzmann', '(895) 5408182'),
('C-30', 'M-030', 'Madelene Hesey', '(973) 8755695'),
('C-31', 'M-031', 'Ezra Herion', '(467) 2962517'),
('C-32', 'M-032', 'Cammy Andreasson', '(811) 3420851'),
('C-33', 'M-033', 'Angelia Samsin', '(597) 4546805'),
('C-34', 'M-034', 'Lena Gianasi', '(429) 3564136'),
('C-35', 'M-035', 'Lydia Vegas', '(233) 8163357'),
('C-36', 'M-036', 'Cammy Leyninye', '(803) 1189454'),
('C-37', 'M-037', 'Trent Crinage', '(832) 9749056'),
('C-38', 'M-038', 'Prent Brannan', '(588) 9626937'),
('C-39', 'M-039', 'Bronson Yakushkev', '(707) 1910607'),
('C-40', 'M-040', 'Agata Brunotti', '(377) 6712267'),
('C-41', 'M-041', 'Arlen Gasparro', '(796) 8662693'),
('C-42', 'M-042', 'Vaclav Bodleigh', '(198) 7713426'),
('C-43', 'M-043', 'Colet Rohlfs', '(243) 7265226'),
('C-44', 'M-044', 'Gaylene Brosius', '(554) 1022016'),
('C-45', 'M-045', 'Cos Pykerman', '(196) 7634288'),
('C-46', 'M-046', 'Salli Lytle', '(381) 5713819'),
('C-47', 'M-047', 'Adelice Jeppe', '(607) 4365206'),
('C-48', 'M-048', 'Desirae Bunston', '(394) 5263664'),
('C-49', 'M-049', 'Bing Landal', '(617) 7102652'),
('C-50', 'M-050', 'Dasya Sharrocks', '(659) 4382849');

/* ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- */

CREATE TABLE part(
	Part_ID varchar(15) PRIMARY KEY,
    Part_Category varchar(25) NOT NULL,
    Part_Quantity varchar(10) NOT NULL,
    Purchase_Price decimal(7,2)
);

INSERT INTO part (Part_ID, Part_Quantity, Part_Category, Purchase_Price) VALUES
('P-0001', 1 , 'engine',  '179.87'),
('P-0002', 3 , 'fuel system', '454.02'),
('P-0003', 1 , 'exhaust system', '662.84'),
('P-0004', 3 , 'fuel system', '927.93'),
('P-0005', 2 , 'exhaust system', '715.57'),
('P-0006', 1 , 'engine', '103.96'),
('P-0007', 2 , 'engine', '34.43'),
('P-0008', 3 , 'fuel system', '962.72'),
('P-0009', 4 , 'exhaust system', '413.63'),
('P-0010', 1 , 'cooling system', '1380.26'),
('P-0011', 1 , 'fuel system', '398.71'),
('P-0012', 2 , 'cooling system', '546.16'),
('P-0013', 1 , 'cooling system', '90.44'),
('P-0014', 4 , 'cooling system', '35.56'),
('P-0015', 4 , 'engine', '284.13'),
('P-0016', 3 , 'fuel system', '452.86'),
('P-0017', 1 , 'engine', '282.16'),
('P-0018', 8 , 'electrical system', '458.16'),
('P-0019', 4 , 'transmission', '725.24'),
('P-0020', 4 , 'fluids', '54.77'),
('P-0021', 1 , 'chassis', null),
('P-0022', 2 , 'transmission', '429.34'),
('P-0023', 3 , 'engine', '495.54'),
('P-0024', 1 , 'fuel system', '111.54'),
('P-0025', 1 , 'transmission', '883.73'),
('P-0026', 2 , 'chassis', '919.85'),
('P-0027', 3 , 'chassis', null),
('P-0028', 2 , 'chassis', '114.27'),
('P-0029', 2 , 'exhaust system', '320.24'),
('P-0030', 3 , 'chassis', '366.40'),
('P-0031', 4 , 'fluids', '285.95'),
('P-0032', 2 , 'exhaust system', '680.50'),
('P-0033', 1 , 'exhaust system', '20.32'),
('P-0034', 1 , 'fluids', '47.96'),
('P-0035', 2 , 'engine', '510.97'),
('P-0036', 6 , 'electrical system', '85.32'),
('P-0037', 1 , 'chassis', '950.84'),
('P-0038', 4 , 'engine', '772.25'),
('P-0039', 2 , 'chassis', '506.63'),
('P-0040', 1 , 'fuel system', '256.46'),
('P-0041', 2 , 'chassis', '49.62'),
('P-0042', 1 , 'chassis', null),
('P-0043', 3 , 'fuel system', '353.76'),
('P-0044', 1 , 'chassis', '601.38'),
('P-0045', 2 , 'cooling system', '442.48'),
('P-0046', 3 , 'fuel system', '528.52'),
('P-0047', 7 , 'electrical system', '50.34'),
('P-0048', 2 , 'transmission', '250.80'),
('P-0049', 6 , 'engine', '657.22'),
('P-0050', 1 , 'fluids', '95.17');

/* ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- */

CREATE TABLE mechanic_uses (
	Mechanic_ID varchar(15),
    Part_ID varchar(15),
    FOREIGN KEY (mechanic_id) references mechanic(mechanic_id),
    FOREIGN KEY (part_id) references part(part_id)
);

INSERT INTO mechanic_uses(mechanic_id, part_id) VALUES
('M-001','P-0001'), 
('M-002','P-0002'), 
('M-003','P-0003'), 
('M-004','P-0004'), 
('M-005','P-0005'), 
('M-006','P-0006'), 
('M-007','P-0007'), 
('M-008','P-0008'), 
('M-009','P-0009'), 
('M-010','P-0010'), 
('M-011','P-0011'), 
('M-012','P-0012'), 
('M-013','P-0013'), 
('M-014','P-0014'), 
('M-015','P-0015'), 
('M-016','P-0016'), 
('M-017','P-0017'), 
('M-018','P-0018'), 
('M-019','P-0019'), 
('M-020','P-0020'), 
('M-021','P-0021'), 
('M-022','P-0022'), 
('M-023','P-0023'), 
('M-024','P-0024'), 
('M-025','P-0025'), 
('M-026','P-0026'), 
('M-027','P-0027'), 
('M-028','P-0028'), 
('M-029','P-0029'), 
('M-030','P-0030'), 
('M-031','P-0031'), 
('M-032','P-0032'), 
('M-033','P-0033'), 
('M-034','P-0034'), 
('M-035','P-0035'), 
('M-036','P-0036'), 
('M-037','P-0037'), 
('M-038','P-0038'), 
('M-039','P-0039'), 
('M-040','P-0040'), 
('M-041','P-0041'), 
('M-042','P-0042'), 
('M-043','P-0043'), 
('M-044','P-0044'), 
('M-045','P-0045'), 
('M-046','P-0046'), 
('M-047','P-0047'), 
('M-048','P-0048'), 
('M-049','P-0049'), 
('M-050','P-0050');

/* ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- */

CREATE TABLE mechanic_performs(
	Mechanic_ID varchar(15),
    Service_ID varchar(15),
	FOREIGN KEY (mechanic_id) references mechanic(mechanic_id),
	FOREIGN KEY (service_id) references service(service_id)
);

INSERT INTO mechanic_performs(mechanic_id, service_id) VALUES
('M-001','S-01'),
('M-002','S-02'),
('M-003','S-03'),
('M-004','S-04'),
('M-005','S-05'),
('M-006','S-06'),
('M-007','S-07'),
('M-008','S-08'),
('M-009','S-09'),
('M-010','S-10'),
('M-011','S-11'),
('M-012','S-12'),
('M-013','S-13'),
('M-014','S-14'),
('M-015','S-15'),
('M-016','S-16'),
('M-017','S-17'),
('M-018','S-18'),
('M-019','S-19'),
('M-020','S-20'),
('M-021','S-21'),
('M-022','S-22'),
('M-023','S-23'),
('M-024','S-24'),
('M-025','S-25'),
('M-026','S-26'),
('M-027','S-27'),
('M-028','S-28'),
('M-029','S-29'),
('M-030','S-30'),
('M-031','S-31'),
('M-032','S-32'),
('M-033','S-33'),
('M-034','S-34'),
('M-035','S-35'),
('M-036','S-36'),
('M-037','S-37'),
('M-038','S-38'),
('M-039','S-39'),
('M-040','S-40'),
('M-041','S-41'),
('M-042','S-42'),
('M-043','S-43'),
('M-044','S-44'),
('M-045','S-45'),
('M-046','S-46'),
('M-047','S-47'),
('M-048','S-48'),
('M-049','S-49'),
('M-050','S-50');

/* ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- */
/* ------------------------------------------------------------------------------------------------- Queries -------------------------------------------------------------------------------------------------------- */
/* ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- */
-- Query 1 --
-- In query 1, it displays the mechanic who used the needed parts to complete their required task. 
-- Not only that but it also displays what part category was used, as well as the total parts that were ordered and how much the utilized parts cost the business.
SELECT mechanic_name "Mechanic" , Part_Category as "Type of Part Ordered" , sum(part_quantity) as " Total Number of Parts Ordered", 
																			sum(purchase_price) as "Cost of Parts Ordered"
	FROM mechanic
	INNER JOIN mechanic_uses
		ON mechanic.mechanic_id = mechanic_uses.mechanic_id
	INNER JOIN part
		ON mechanic_uses.part_id = part.part_id
    GROUP BY mechanic_name, part_category
    ORDER BY sum(Part_Quantity)desc, Part_Category asc;

    
-- Query 2--
-- In query 2, it simply shows the average price parts are paid by the business. 
-- This can allow the business to analyze a trend and determine what part category costs the business the most.

SELECT part_category as "Part Category", avg(purchase_price) as "Average Price Paid for Part(s)"
	FROM part
    GROUP BY part_category 
    ORDER BY avg(purchase_price) desc;

    
-- Query 3--
-- In query 3, it again shows the average price parts are paid by the business. 
-- Now this shows the average quantity of parts that are purchased as well.
SELECT part_category, avg(purchase_price), avg(part_quantity)
	FROM part
    GROUP BY part_category
    ORDER BY avg(Purchase_Price) desc;


-- Query 4--
-- In query 4, it shows what type of parts are being utilized and purchased the most. 
-- This again can analyze and determine whether there is a trend in the following years.
SELECT Part_Category, COUNT(part_category) as "Most Used and Purchased Part Category"
	FROM part
    GROUP BY part_category
    ORDER BY COUNT(part_category) desc;



-- Query 5--
-- In query 5, this example aims to show how mechanics are now provided information on what vehicles are still in need of service. 
-- This query’s main goal is to eliminate any confusion or doubt. We do not want other mechanics that are assigned to another vehicle to work on a vehicle that is not assigned to them. 
-- The exception is if another mechanic currently does not have any appointments to service another vehicle. In this case, he will be allowed to help the mechanic assigned to the vehicle. 
-- The responsibility to complete the service will not fall on the mechanic trying to help, but rather the mechanic originally assigned to the vehicle.
SELECT Mechanic_Name, customer_name, start_date, service_status
	FROM mechanic 
    INNER JOIN mechanic_performs
		ON mechanic.Mechanic_ID = mechanic_performs.Mechanic_ID
	INNER JOIN customer
		ON customer.Customer_ID = mechanic.Customer_ID
	INNER JOIN service
		ON mechanic_performs.service_ID = service.service_id
	WHERE Service_Status = 'incomeplete'
    ORDER BY start_date asc;
    
    
-- Query 6--
-- In query 6,  this simply shows the average day it takes for the mechanics within the business complete a vehicle service. 
-- This data can help the management team decide whether the mechanics are performing at a proper and efficient pace.
SELECT avg(datediff(finish_Date, start_date)) as "Average Day(s) To Complete a Vehicle Service"
	FROM vehicle
    INNER JOIN vehicle_receives
		ON vehicle.vin = vehicle_receives.vin
	INNER JOIN service
		ON vehicle_receives.service_id = service.service_id
	WHERE service_status = 'complete'
    ORDER BY avg(datediff(finish_Date, start_date)) desc;


-- Query 7--
-- In query 7, this data shows the mechanics that were assigned to a certain vehicle as well as the parts that they utilized to complete their service for a specific vehicle. 
-- This can help avoid confusion as it shows which mechanic has used part and where that part was used to complete a service for a customer.
SELECT mechanic_name as "Mechanic", part_category as "Part Category Used", part_quantity as "Parts Used", make as "Vehicle Make" , customer_name as "Customer Name",  total_bill as "Total Customer Bill"
	FROM mechanic
    INNER JOIN mechanic_uses
		ON mechanic.mechanic_id = mechanic_uses.mechanic_id
	INNER JOIN part
		ON mechanic_uses.part_id = part.part_id
	INNER JOIN customer
		ON customer.customer_id = mechanic.customer_id
	INNER JOIN vehicle
		ON customer.customer_id = vehicle.customer_id
	INNER JOIN bill
		ON customer.customer_id = bill.customer_id
	ORDER BY total_bill desc;
        
    
-- Query 8--
-- In query 8, this data is simply aimed for the upper-level management team or business leaders. It shows the profit that the business made from a certain service. 
-- To do this, we simply subtract the price we paid for the parts from the bill that a customer paid. The result shows the difference from how much the company paid for the part and how much the company charged the customer. 
-- Note, this does not consider any wages that we owe the mechanics assigned to the job or other expenses the business may have incurred from the service.
SELECT purchase_price as "Price Paid for Part(s)", total_bill as "Price Customer Paid for Service",(total_bill-purchase_price) as "Revenue - Expenses (*Wages Not Accounted For*)"
	FROM mechanic
    INNER JOIN mechanic_uses
		ON mechanic.mechanic_id = mechanic_uses.mechanic_id
	INNER JOIN part
		ON mechanic_uses.part_id = part.part_id
	INNER JOIN customer
		ON customer.customer_id = mechanic.customer_id
	INNER JOIN vehicle
		ON customer.customer_id = vehicle.customer_id
	INNER JOIN bill
		ON customer.customer_id = bill.customer_id
    ORDER BY (Total_Bill-Purchase_Price)desc;
    
    
-- Query 9--
-- In query 9, this data is aimed at analyzing the amount of time it takes to complete a service from a certain vehicle make. 
-- Some vehicles are more complexed than others so it can be important to know vehicle makes will need more attention and help servicing.
SELECT make, avg(datediff(finish_Date, start_date)) as "Average Day(s) To Complete a Vehicle Service"
	FROM service
	INNER JOIN vehicle_receives
		ON service.service_id = vehicle_receives.service_id
	INNER JOIN vehicle
		ON vehicle_receives.vin = vehicle.vin
	WHERE service_status = 'complete'
	GROUP BY make
    ORDER BY avg(datediff(finish_Date, start_date)) desc;
    
    
-- Query 10--
-- In query 10, This data can help the business determine the parts more frequently used and therefore need more stock of. 
-- This can help avoid stock shortages if the business always has parts that are always in need. 
-- If a certain vehicle make seems to appear more for a service, it might be wise to have more parts in stock for that certain vehicle make.
SELECT make, count(*) as "Most Frequent Vehicle Make"
	FROM vehicle
    GROUP BY make
    ORDER BY count(*) desc;
    
    
-- Query 11--
-- In query 11, this data can be used to analyze any potential trend. 
-- If a certain vehicle make always seems to have a higher bill compared to others, understanding why could help the business determine whether it is the parts that are expensive, or the labor that goes into the service.
SELECT make as "Manufacturer" , sum(total_bill) as "Total Bill Per Car Manufacturer Serviced"
	FROM customer
	INNER JOIN vehicle
		ON customer.customer_id = vehicle.customer_id
	INNER JOIN bill
		ON customer.customer_id = bill.customer_id
	GROUP BY make
    ORDER BY sum(total_bill) desc;
    
    
-- Query 12--
-- In query 12, this data is used to determine what part category costs the business the most. 
-- If a trend is present, the business can try and work with other business who sell or manufacture those parts for a business deal that can potentially decrease the expense for the business while also increasing the revenue.
SELECT part_category, sum(purchase_price) 
	FROM part
    GROUP BY part_category
    ORDER BY sum(purchase_price) desc;


-- Query 13--
-- In query 13, this shows the mechanic that worked on a customer’s vehicle and the number of days it took for them to complete the vehicle service. 
-- This can be used to determine if the days needed to complete the service is justifiable. If not, the management team can take further actions to find out why a mechanic needed more time to complete a service.
SELECT Mechanic_Name as "Mechanic", customer_name as "Customer" ,Service_Status, Start_date, Finish_Date, datediff(finish_Date, start_date) as "Days Needed To Complete Service"
	FROM mechanic
	INNER JOIN customer
		ON customer.customer_id = mechanic.customer_id
	INNER JOIN mechanic_performs
		ON mechanic.mechanic_id = mechanic_performs.mechanic_id
	INNER JOIN service
		ON mechanic_performs.service_id = service.service_id
	WHERE Service_Status = 'complete'
    ORDER BY start_date asc;
    
    
-- Query 14--
-- In query 14, this shows what payment type seems to be used most often. A business can try and make a business deal with the companies that are used the most within the business to offer customers an incentive to use a certain payment type for the business. 
-- This can be higher cash back percentages for the customers or the business can make their own card with the help of the credit card company to provide another type of incentive for the customers.
SELECT payment_type, sum(total_bill) as "Total Amount From Payment Type", COUNT(Payment_Type) as "Number of Times Payment Type Used"
	FROM bill
	GROUP BY Payment_Type
    ORDER BY sum(total_bill) desc;
    
    
-- Query 15--
-- In query 15, this simply shows the appointment dates that a customer has with the business as well as their corresponding vehicle information. 
-- This can help the business prepare in advance to make sure that they at least have the very basic parts needed for the service.
SELECT Appt_Date, Customer_Name, Telephone_Number, Make, Model, Year
	FROM customer 
    INNER JOIN vehicle
		ON customer.Customer_ID = vehicle.customer_id
	LEFT OUTER JOIN appointment
		ON customer.customer_id = appointment.customer_id
	WHERE Appt_Date BETWEEN '2021-01-01' AND '2021-04-30'
    ORDER BY appt_date asc;
    
    

SELECT payment_type, total_bill
	FROM bill
    WHERE total_bill >= 500 
	ORDER BY total_bill desc;
    

SELECT *
	FROM appointment
    WHERE appt_date BETWEEN '2021-08-01' AND '2021-12-07'
    ORDER BY appt_date asc;


SELECT make as "Vehicle Manufacturer" , year as "Year Manufactured"
	FROM vehicle
	WHERE year > 2000
    AND make = 'Honda' OR make = 'Toyota'
    ORDER BY year asc;

SELECT appt_date, customer_name
	FROM customer LEFT OUTER JOIN appointment
    ON customer.customer_id = appointment.customer_id
    WHERE appt_date > '2021-08-01'
    ORDER BY appt_date desc;


/* ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- */
/* ------------------------------------------------------------------------------------------------ Data Update --------------------------------------------------------------------------------------------------------- */
/* ----------------------------------------------------------------------------------***Not Included In Provided SQL examples**--------------------------------------------------------------------------------------------- */
/* -----------------------------------------------------------------------------**Given Query Results Do Not Reflect Updated Data**-------------------------------------------------------------------------------------- */


UPDATE customer
	SET telephone_number = '(801) 9581563'
    WHERE customer_id = 'C-17';
    
UPDATE mechanic
	SET mechanic_name = 'AJ Hunter'
    WHERE phone_number = '(605) 2159905';

UPDATE service
	SET service_status = 'Complete', finish_date = '2021/11/30'
    WHERE service_id = 'S-13';
    
UPDATE bill
	SET total_bill = total_bill * .80
    WHERE bill_number = 'B-0011';

UPDATE appointment
	SET appt_date = '2021-04-25'
    WHERE appt_number = 'A-21';

UPDATE vehicle
	SET year = '2007'
    WHERE VIN = '5J6TF2H59EL253132';

UPDATE part
	SET purchase_price = '460.49'
    WHERE part_id = 'P-0047';

/* ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- */
/* ------------------------------------------------------------------------------------------------- Data Delete -------------------------------------------------------------------------------------------------------- */
/* -----------------------------------------------------------------------------------***Not Included In Provided SQL examples**----------------------------------------------------------------------------------------- */
/* -----------------------------------------------------------------------------**Given Query Results Do Not Reflect Deleted Data**-------------------------------------------------------------------------------------- */


DELETE 
	FROM customer
    WHERE customer_id = 'C-06';
    
DELETE
	FROM mechanic
    WHERE mechanic_id = 'M-043';
    
DELETE 
	FROM service
    WHERE service_date = '2021/01/25';
    
DELETE 
	FROM bill
    WHERE total_bill = '40.41';
    
DELETE 
	FROM appointment
    WHERE appt_time = '4:42 PM';

DELETE 
	FROM vehicle
    WHERE make = 'Mazda'
    AND model = 'Navajo';
    
DELETE 
	FROM part
    WHERE purchase_price = "P-0021";
